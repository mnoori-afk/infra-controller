/*
 * SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

use std::future::Future;
use std::time::Duration;

use ::rpc::forge::InstanceReleaseRequest;
use carbide_uuid::instance::InstanceId;

use super::args::Args;
use crate::cfg::runtime::RuntimeContext;
use crate::errors::{CarbideCliError, CarbideCliResult};
use crate::rpc::ApiClient;

/// gRPC metadata key the API attaches to a `RESOURCE_EXHAUSTED` admission
/// rejection, carrying the advertised backoff in whole milliseconds. Must match
/// `GRPC_RETRY_PUSHBACK_HEADER` in `api-core/src/admission/mod.rs`.
const ADMISSION_RETRY_PUSHBACK_HEADER: &str = "grpc-retry-pushback-ms";
/// Batch-wide cumulative backoff cap: once we've spent this long backing off
/// since the last successful release, the backend is considered persistently
/// saturated -- stop attempting further instances rather than retrying
/// indefinitely. Shared across the whole batch (not per-instance) and reset to
/// zero on every success, so a single bad stretch doesn't strand instances that
/// would have gone through once the backend recovered.
const MAX_TOTAL_BACKOFF: Duration = Duration::from_secs(120);
/// Backoff used when the server omits an (unexpected) parseable pushback value.
const DEFAULT_ADMISSION_BACKOFF: Duration = Duration::from_secs(5);
/// Bounds mirroring the server's own advertised range in `admission/retry.rs`.
const MIN_ADMISSION_BACKOFF: Duration = Duration::from_secs(1);
const MAX_ADMISSION_BACKOFF: Duration = Duration::from_secs(30);

/// Parses the server-advertised retry delay from a rejection's metadata.
fn admission_retry_delay(status: &tonic::Status) -> Option<Duration> {
    let millis = status
        .metadata()
        .get(ADMISSION_RETRY_PUSHBACK_HEADER)?
        .to_str()
        .ok()?
        .parse::<u64>()
        .ok()?;
    Some(Duration::from_millis(millis))
}

/// Delay for the `n`th consecutive `RESOURCE_EXHAUSTED` rejection (`n` >= 1),
/// growing linearly with the server's own advertised pushback as the unit:
/// `pushback * n`, clamped to the server's advertised range.
///
/// Linear, not exponential: the server's advertised delay is already computed
/// from live load (EWMA/queue-depth in `admission/retry.rs`), so it grows on
/// its own as pressure increases. Multiplying an already load-aware signal by
/// an exponential factor on top would compound backoff unnecessarily and hurt
/// throughput once the backend recovers. Linear growth still backs off harder
/// under sustained saturation than reusing the same delay every time (which
/// risks the client itself contributing to the saturation it's retrying
/// against), without that compounding.
fn linear_admission_backoff(status: &tonic::Status, consecutive_exhaustions: u32) -> Duration {
    admission_retry_delay(status)
        .unwrap_or(DEFAULT_ADMISSION_BACKOFF)
        .saturating_mul(consecutive_exhaustions.max(1))
        .clamp(MIN_ADMISSION_BACKOFF, MAX_ADMISSION_BACKOFF)
}

/// Retries a fallible CLI call that fails with a `RESOURCE_EXHAUSTED`
/// admission rejection, backing off linearly (see [`linear_admission_backoff`])
/// and bounded by [`MAX_TOTAL_BACKOFF`] cumulative wait. Any other error
/// surfaces immediately so real failures are not masked.
///
/// Motivation: resolving `--label-key`/`--machine` into a concrete instance
/// list (`get_all_instances` / `find_instance_by_machine_id`) happens before
/// `release_batch` and its own retry logic ever runs. Without this, a
/// `RESOURCE_EXHAUSTED` rejection on that single preflight call aborted the
/// whole release with zero instances attempted, even though the batch loop
/// itself was already retry-safe -- observed live at ~4,500-host scale, where
/// under sustained admission pressure some release invocations failed
/// instantly with no progress purely because this one lookup call landed in
/// a saturated window.
async fn retry_cli_call_on_admission_exhaustion<T, F, Fut>(mut attempt: F) -> CarbideCliResult<T>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = CarbideCliResult<T>>,
{
    let mut consecutive_exhaustions: u32 = 0;
    let mut total_backoff = Duration::ZERO;
    loop {
        match attempt().await {
            Ok(value) => return Ok(value),
            Err(CarbideCliError::ApiInvocationError(status))
                if status.code() == tonic::Code::ResourceExhausted =>
            {
                consecutive_exhaustions += 1;
                let delay = linear_admission_backoff(&status, consecutive_exhaustions);
                if total_backoff.saturating_add(delay) > MAX_TOTAL_BACKOFF {
                    return Err(CarbideCliError::ApiInvocationError(status));
                }
                total_backoff = total_backoff.saturating_add(delay);
                tokio::time::sleep(delay).await;
            }
            Err(other) => return Err(other),
        }
    }
}

/// Result of releasing a batch of instances.
struct BatchReleaseOutcome {
    released: usize,
    /// Instances that were attempted (with retries) but ultimately failed.
    failures: Vec<(InstanceId, tonic::Status)>,
    /// Instances skipped because the batch-wide backoff budget was exhausted.
    not_attempted: Vec<InstanceId>,
}

/// Releases each instance in turn. `RESOURCE_EXHAUSTED` admission rejections
/// retry the *same* instance after a linearly-growing backoff (see
/// [`linear_admission_backoff`]); any other error is recorded as a failure and
/// the loop moves on, so one stuck instance cannot strand the rest.
///
/// The backoff state -- consecutive-exhaustion count and cumulative backoff
/// time -- is shared across the *entire batch*, not tracked per instance: a
/// success on any instance resets both back to zero. This reflects the real
/// failure mode observed live at ~4,500-instance scale -- admission exhaustion
/// is a shared, backend-wide condition, not an independent property of each
/// instance, so treating it as one continuously-adjusting operation-level
/// budget (instead of restarting a fresh per-instance clock/attempt-count for
/// every item) recovers faster once the backend has room again, and gives up
/// sooner -- via [`MAX_TOTAL_BACKOFF`] elapsed since the last success -- when
/// it genuinely hasn't, rather than needing several instances to each burn a
/// full independent retry budget before noticing the backend is saturated.
///
/// `release_one` is injected so the batch/continuation logic is exercised
/// directly in tests without a live gRPC client.
async fn release_batch<F, Fut>(
    instance_ids: Vec<InstanceId>,
    mut release_one: F,
) -> BatchReleaseOutcome
where
    F: FnMut(InstanceId) -> Fut,
    Fut: Future<Output = Result<(), tonic::Status>>,
{
    let mut released = 0usize;
    let mut failures = Vec::new();
    let mut not_attempted = Vec::new();
    let mut consecutive_exhaustions: u32 = 0;
    let mut backoff_since_last_success = Duration::ZERO;

    let mut remaining = instance_ids.into_iter();
    'batch: while let Some(instance_id) = remaining.next() {
        loop {
            match release_one(instance_id).await {
                Ok(()) => {
                    released += 1;
                    consecutive_exhaustions = 0;
                    backoff_since_last_success = Duration::ZERO;
                    continue 'batch;
                }
                Err(status) if status.code() == tonic::Code::ResourceExhausted => {
                    consecutive_exhaustions += 1;
                    let delay = linear_admission_backoff(&status, consecutive_exhaustions);

                    if backoff_since_last_success.saturating_add(delay) > MAX_TOTAL_BACKOFF {
                        tracing::error!(
                            instance_id = %instance_id,
                            "Failed to release instance: {}",
                            status.message()
                        );
                        failures.push((instance_id, status));
                        not_attempted.extend(remaining);
                        break 'batch;
                    }

                    backoff_since_last_success =
                        backoff_since_last_success.saturating_add(delay);
                    tokio::time::sleep(delay).await;
                    // Retry the same instance; it was never actually released.
                }
                Err(status) => {
                    tracing::error!(
                        instance_id = %instance_id,
                        code = ?status.code(),
                        "Failed to release instance: {}",
                        status.message()
                    );
                    failures.push((instance_id, status));
                    consecutive_exhaustions = 0;
                    backoff_since_last_success = Duration::ZERO;
                    continue 'batch;
                }
            }
        }
    }

    BatchReleaseOutcome {
        released,
        failures,
        not_attempted,
    }
}

pub(super) async fn release(
    api_client: &ApiClient,
    release_request: Args,
    ctx: &RuntimeContext,
) -> CarbideCliResult<()> {
    ctx.assert_cloud_unsafe_op_message()?;

    let mut instance_ids: Vec<InstanceId> = Vec::new();

    match (
        release_request.instance,
        release_request.machine,
        release_request.label_key,
    ) {
        (Some(instance_id), _, _) => instance_ids.push(
            uuid::Uuid::parse_str(&instance_id)
                .map_err(|e| CarbideCliError::GenericError(e.to_string()))?
                .into(),
        ),
        (_, Some(machine_id), _) => {
            let instances = retry_cli_call_on_admission_exhaustion(|| async {
                api_client
                    .0
                    .find_instance_by_machine_id(machine_id)
                    .await
                    .map_err(CarbideCliError::from)
            })
            .await?
            .instances;
            let Some(instance_id) = instances.into_iter().next().and_then(|i| i.id) else {
                return Err(CarbideCliError::GenericError(
                    "No instances assigned to that machine".to_string(),
                ));
            };
            instance_ids.push(instance_id);
        }
        (_, _, Some(key)) => {
            let label_value = release_request.label_value.clone();
            let instances = retry_cli_call_on_admission_exhaustion(|| {
                api_client.get_all_instances(
                    None,
                    None,
                    Some(key.clone()),
                    label_value.clone(),
                    None,
                    ctx.config.page_size,
                )
            })
            .await?;
            if instances.instances.is_empty() {
                return Err(CarbideCliError::GenericError(
                    "No instances with the passed label.key exist".to_string(),
                ));
            }
            instance_ids = instances
                .instances
                .iter()
                .filter_map(|instance| instance.id)
                .collect();
        }
        _ => {}
    };
    let total = instance_ids.len();

    let outcome = release_batch(instance_ids, |instance_id| async move {
        api_client
            .0
            .release_instance(InstanceReleaseRequest {
                id: Some(instance_id),
                issue: None,
                is_repair_tenant: None,
                delete_attribution: None,
            })
            .await
            .map(|_| ())
    })
    .await;

    let BatchReleaseOutcome {
        released,
        failures,
        not_attempted,
    } = outcome;

    if failures.is_empty() && not_attempted.is_empty() {
        tracing::info!("Released {total} instance(s).");
        return Ok(());
    }

    tracing::error!(
        "Released {released}/{total} instance(s); {} failed, {} not attempted:",
        failures.len(),
        not_attempted.len()
    );
    for (instance_id, status) in &failures {
        tracing::error!(
            instance_id = %instance_id,
            "  {} ({:?})",
            status.message(),
            status.code()
        );
    }
    if !not_attempted.is_empty() {
        tracing::error!(
            "Stopped after {MAX_TOTAL_BACKOFF:?} of cumulative admission backoff with no \
             progress (backend saturated); {} instance(s) not attempted.",
            not_attempted.len()
        );
    }
    Err(CarbideCliError::GenericError(format!(
        "release incomplete: {} failed, {} not attempted of {total} instance(s) (see logs above)",
        failures.len(),
        not_attempted.len()
    )))
}

#[cfg(test)]
mod tests {
    use std::cell::Cell;

    use tonic::metadata::MetadataValue;

    use super::*;

    fn exhausted(pushback_millis: u64) -> tonic::Status {
        let mut status = tonic::Status::resource_exhausted("API admission capacity exhausted");
        status.metadata_mut().insert(
            ADMISSION_RETRY_PUSHBACK_HEADER,
            MetadataValue::try_from(pushback_millis.to_string().as_str()).unwrap(),
        );
        status
    }

    #[test]
    fn parses_advertised_pushback_delay() {
        assert_eq!(
            admission_retry_delay(&exhausted(7_000)),
            Some(Duration::from_secs(7))
        );
        assert_eq!(
            admission_retry_delay(&tonic::Status::resource_exhausted("no header")),
            None
        );
    }

    #[test]
    fn linear_backoff_grows_with_consecutive_count_and_clamps() {
        let status = exhausted(5_000);
        assert_eq!(linear_admission_backoff(&status, 1), Duration::from_secs(5));
        assert_eq!(linear_admission_backoff(&status, 2), Duration::from_secs(10));
        // Clamped to MAX_ADMISSION_BACKOFF regardless of how large the linear
        // product gets.
        assert_eq!(
            linear_admission_backoff(&status, 100),
            MAX_ADMISSION_BACKOFF
        );
    }

    #[test]
    fn linear_backoff_falls_back_to_default_without_advertised_delay() {
        let status = tonic::Status::resource_exhausted("no pushback header");
        assert_eq!(
            linear_admission_backoff(&status, 1),
            DEFAULT_ADMISSION_BACKOFF
        );
    }

    #[tokio::test(start_paused = true)]
    async fn preflight_retries_same_call_with_growing_linear_backoff_then_succeeds() {
        let attempts = Cell::new(0);
        let start = tokio::time::Instant::now();

        let result = retry_cli_call_on_admission_exhaustion(|| {
            let attempt = attempts.get() + 1;
            attempts.set(attempt);
            async move {
                if attempt < 3 {
                    Err(CarbideCliError::ApiInvocationError(exhausted(5_000)))
                } else {
                    Ok(42)
                }
            }
        })
        .await;

        assert_eq!(result.unwrap(), 42);
        assert_eq!(attempts.get(), 3);
        // First rejection backs off 5s (5s * 1), second backs off 10s (5s * 2):
        // growing linearly, not the same delay reused each time.
        assert_eq!(start.elapsed(), Duration::from_secs(15));
    }

    #[tokio::test(start_paused = true)]
    async fn preflight_gives_up_after_cumulative_backoff_budget_exhausted() {
        let attempts = Cell::new(0);

        let result = retry_cli_call_on_admission_exhaustion(|| {
            attempts.set(attempts.get() + 1);
            async move { Err::<(), _>(CarbideCliError::ApiInvocationError(exhausted(10_000))) }
        })
        .await;

        match result.unwrap_err() {
            CarbideCliError::ApiInvocationError(status) => {
                assert_eq!(status.code(), tonic::Code::ResourceExhausted);
            }
            other => panic!("expected ApiInvocationError, got {other:?}"),
        }
        // Delays: 10s, 20s, 30s, 30s (clamped from 40s), 30s (clamped from
        // 50s) -- cumulative exactly 120s, still within budget. The 6th call's
        // would-be 30s delay (clamped from 60s) pushes cumulative to 150s,
        // exceeding MAX_TOTAL_BACKOFF, so it gives up instead of sleeping.
        assert_eq!(attempts.get(), 6);
    }

    #[tokio::test(start_paused = true)]
    async fn preflight_non_admission_errors_surface_without_retry() {
        let attempts = Cell::new(0);

        let result = retry_cli_call_on_admission_exhaustion(|| {
            attempts.set(attempts.get() + 1);
            async move {
                Err::<(), _>(CarbideCliError::ApiInvocationError(tonic::Status::not_found(
                    "gone",
                )))
            }
        })
        .await;

        match result.unwrap_err() {
            CarbideCliError::ApiInvocationError(status) => {
                assert_eq!(status.code(), tonic::Code::NotFound);
            }
            other => panic!("expected ApiInvocationError, got {other:?}"),
        }
        assert_eq!(attempts.get(), 1);
    }

    fn instance_ids(count: u128) -> Vec<InstanceId> {
        (1..=count)
            .map(|n| uuid::Uuid::from_u128(n).into())
            .collect()
    }

    #[tokio::test(start_paused = true)]
    async fn batch_continues_past_a_failed_instance() {
        // Exercises the real `release_batch` path: the middle instance fails
        // (non-admission), yet the rest still get attempted and released.
        let ids = instance_ids(3);
        let stuck = ids[1];

        let outcome = release_batch(ids, |instance_id| async move {
            if instance_id == stuck {
                Err(tonic::Status::not_found("gone"))
            } else {
                Ok(())
            }
        })
        .await;

        assert_eq!(outcome.released, 2);
        assert_eq!(outcome.failures.len(), 1);
        assert_eq!(outcome.failures[0].0, stuck);
        assert!(outcome.not_attempted.is_empty());
    }

    #[tokio::test(start_paused = true)]
    async fn batch_retries_same_instance_in_place_with_growing_backoff_then_succeeds() {
        // The first instance is admission-exhausted twice, retried in place
        // (not skipped/moved past) each time with a growing delay, then
        // succeeds on the third attempt; the rest of the batch proceeds
        // normally.
        let ids = instance_ids(2);
        let first = ids[0];
        let attempts = Cell::new(0);

        let outcome = release_batch(ids, |instance_id| {
            let attempt = if instance_id == first {
                let n = attempts.get() + 1;
                attempts.set(n);
                n
            } else {
                0
            };
            async move {
                if instance_id == first && attempt < 3 {
                    Err(exhausted(1_000))
                } else {
                    Ok(())
                }
            }
        })
        .await;

        assert_eq!(attempts.get(), 3);
        assert_eq!(outcome.released, 2);
        assert!(outcome.failures.is_empty());
        assert!(outcome.not_attempted.is_empty());
    }

    #[tokio::test(start_paused = true)]
    async fn batch_gives_up_after_cumulative_backoff_budget_exhausted() {
        // Every instance is admission-exhausted forever: cumulative backoff
        // (shared across the whole batch, growing linearly per consecutive
        // rejection) exceeds MAX_TOTAL_BACKOFF while retrying the very first
        // instance, so the batch gives up on it and leaves the rest
        // unattempted -- without needing several separate instances to each
        // burn an independent budget first.
        let ids = instance_ids(3);

        let outcome = release_batch(ids, |_instance_id| async move { Err(exhausted(10_000)) }).await;

        assert_eq!(outcome.released, 0);
        assert_eq!(outcome.failures.len(), 1);
        assert_eq!(outcome.not_attempted.len(), 2);
    }

    #[tokio::test(start_paused = true)]
    async fn batch_backoff_resets_on_progress_across_instances() {
        // Every instance is admission-exhausted exactly once, then succeeds on
        // retry. If the shared backoff state correctly resets to zero on every
        // success, the whole batch completes -- accumulated backoff from an
        // earlier instance must not carry over and strand a later one.
        let ids = instance_ids(10);
        let failed_once = std::cell::RefCell::new(std::collections::HashSet::new());

        let outcome = release_batch(ids, move |instance_id| {
            let first_attempt = failed_once.borrow_mut().insert(instance_id);
            async move {
                if first_attempt {
                    Err(exhausted(1_000))
                } else {
                    Ok(())
                }
            }
        })
        .await;

        assert_eq!(outcome.released, 10);
        assert!(outcome.failures.is_empty());
        assert!(outcome.not_attempted.is_empty());
    }
}
