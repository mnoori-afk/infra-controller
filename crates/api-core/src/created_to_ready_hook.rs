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

//! Post-commit state-change hook recording wall-clock ingestion duration
//! when a host machine enters [`ManagedHostState::Ready`].

use carbide_instrument::{Event, emit};
use carbide_uuid::machine::MachineId;
use chrono::{DateTime, Utc};
use model::machine::ManagedHostState;
use sqlx::PgPool;
use state_controller::state_change_emitter::{StateChangeEvent, StateChangeHook};

/// Wall-clock ingestion duration, emitted when a host machine enters
/// [`ManagedHostState::Ready`] from a different state. Fired from the
/// post-commit state-change hook, so a rolled-back or conflicted transition
/// can never record an observation.
#[derive(Event)]
#[event(
    event_name = "machine_created_to_ready",
    metric_name = "carbide_machine_created_to_ready_duration_seconds",
    component = "nico-api",
    log = info,
    metric = histogram,
    message = "Machine reached Ready",
    describe = "Wall-clock time from machine-row creation to an entry into the Ready state, in seconds"
)]
struct MachineCreatedToReady {
    #[context]
    machine_id: String,
    #[observation]
    duration_s: u64,
}

/// The hook behind `carbide_machine_created_to_ready_duration_seconds`.
pub struct CreatedToReadyMetricHook {
    db_pool: PgPool,
}

impl CreatedToReadyMetricHook {
    pub fn new(db_pool: PgPool) -> Self {
        Self { db_pool }
    }
}

impl StateChangeHook<MachineId, ManagedHostState> for CreatedToReadyMetricHook {
    fn on_state_changed(&self, event: &StateChangeEvent<'_, MachineId, ManagedHostState>) {
        // Entries into Ready only. A re-committed Ready (the
        // transition-to-current-state case) must not re-observe the
        // machine's whole age as an ingestion duration.
        if !matches!(event.new_state, ManagedHostState::Ready)
            || matches!(event.previous_state, Some(ManagedHostState::Ready))
        {
            return;
        }
        let pool = self.db_pool.clone();
        let machine_id = event.object_id.to_string();
        let reached_ready_at = event.timestamp;
        // Hooks are synchronous by contract; do the read on a background task.
        tokio::spawn(async move {
            let created: Result<Option<DateTime<Utc>>, sqlx::Error> =
                sqlx::query_scalar("SELECT created FROM machines WHERE id = $1")
                    .bind(&machine_id)
                    .fetch_optional(&pool)
                    .await;
            match created {
                Ok(Some(created)) => emit(MachineCreatedToReady {
                    machine_id,
                    duration_s: (reached_ready_at - created).num_seconds().max(0) as u64,
                }),
                // Deleted between the commit and this read; nothing to record.
                Ok(None) => {}
                Err(error) => tracing::warn!(
                    %machine_id,
                    ?error,
                    "could not read machines.created for the created-to-ready metric"
                ),
            }
        });
    }
}
