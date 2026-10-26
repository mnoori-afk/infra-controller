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

//! Census rules: how one unit type is read (a census of IDs, then by-ID reads
//! in batches).
//!
//! A count never includes a unit the probe did not read. An ID the by-ID read
//! did not return is looked up once more in a fresh census: gone from it, the
//! unit was deleted mid-sweep and is not counted; still in it, the unit is
//! unresolved and its family keeps the last snapshot.

use std::collections::{BTreeMap, BTreeSet};
use std::future::Future;

use crate::gate::CallError;

/// One unit type's by-ID read, keyed by unit ID.
#[derive(Debug)]
pub(crate) struct CensusRead<R> {
    pub rows: BTreeMap<String, R>,
    /// Missing from the by-ID read and from the second census: deleted.
    pub gone: BTreeSet<String>,
    /// Missing from the by-ID read but still in the second census.
    pub unresolved: BTreeSet<String>,
}

/// Reads every census ID once, `batch` IDs per by-ID call. Rows the call was
/// not asked for, and repeats, are dropped. Misses get one second census
/// (`recensus`) that tells gone from unresolved.
pub(crate) async fn read_family<R, F, Fut, C, CFut>(
    census: Vec<String>,
    batch: usize,
    mut fetch: F,
    id_of: fn(&R) -> String,
    recensus: C,
) -> Result<CensusRead<R>, CallError>
where
    F: FnMut(Vec<String>) -> Fut,
    Fut: Future<Output = Result<Vec<R>, CallError>>,
    C: FnOnce() -> CFut,
    CFut: Future<Output = Result<Vec<String>, CallError>>,
{
    let ids: Vec<String> = census
        .into_iter()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();
    let mut rows = BTreeMap::new();
    for chunk in ids.chunks(batch.max(1)) {
        let asked: BTreeSet<&String> = chunk.iter().collect();
        for row in fetch(chunk.to_vec()).await? {
            let id = id_of(&row);
            if asked.contains(&id) && !rows.contains_key(&id) {
                rows.insert(id, row);
            }
        }
    }
    let missing: Vec<&String> = ids.iter().filter(|id| !rows.contains_key(*id)).collect();
    let mut gone = BTreeSet::new();
    let mut unresolved = BTreeSet::new();
    if !missing.is_empty() {
        let again: BTreeSet<String> = recensus().await?.into_iter().collect();
        for id in missing {
            if again.contains(id) {
                unresolved.insert(id.clone());
            } else {
                gone.insert(id.clone());
            }
        }
    }
    Ok(CensusRead {
        rows,
        gone,
        unresolved,
    })
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;

    use super::*;

    #[derive(Debug, Clone, PartialEq)]
    struct Row {
        id: String,
        n: u32,
    }

    fn row(id: &str, n: u32) -> Row {
        Row {
            id: id.to_string(),
            n,
        }
    }

    fn ids(list: &[&str]) -> Vec<String> {
        list.iter().map(|id| id.to_string()).collect()
    }

    #[tokio::test]
    async fn census_counts_each_id_once() {
        let asked = Mutex::new(Vec::new());
        let read = read_family(
            ids(&["a", "b", "a", "c", "b"]),
            2,
            |batch| {
                asked.lock().unwrap().push(batch.clone());
                async move { Ok(batch.iter().map(|id| row(id, 1)).collect()) }
            },
            |r: &Row| r.id.clone(),
            || async { Ok(vec![]) },
        )
        .await
        .expect("read");
        assert_eq!(read.rows.len(), 3);
        assert_eq!(
            *asked.lock().unwrap(),
            vec![ids(&["a", "b"]), ids(&["c"])],
            "each ID asked once, in batches"
        );
        assert!(read.gone.is_empty() && read.unresolved.is_empty());
    }

    #[tokio::test]
    async fn by_id_extra_and_repeated_rows_dropped() {
        let read = read_family(
            ids(&["a", "b"]),
            100,
            |_batch| async {
                Ok(vec![
                    row("a", 1),
                    row("a", 2),
                    row("stranger", 1),
                    row("b", 1),
                ])
            },
            |r: &Row| r.id.clone(),
            || async { Ok(vec![]) },
        )
        .await
        .expect("read");
        assert_eq!(read.rows.keys().collect::<Vec<_>>(), ["a", "b"]);
        assert_eq!(read.rows["a"].n, 1, "the first row of a repeated ID wins");
    }

    #[tokio::test]
    async fn missing_id_gone_vs_unresolved() {
        let recensus_calls = Mutex::new(0);
        let read = read_family(
            ids(&["a", "deleted", "stuck"]),
            100,
            |_batch| async { Ok(vec![row("a", 1)]) },
            |r: &Row| r.id.clone(),
            || {
                *recensus_calls.lock().unwrap() += 1;
                async { Ok(ids(&["a", "stuck", "new"])) }
            },
        )
        .await
        .expect("read");
        assert_eq!(read.rows.len(), 1);
        assert_eq!(read.gone, BTreeSet::from(["deleted".to_string()]));
        assert_eq!(read.unresolved, BTreeSet::from(["stuck".to_string()]));
        assert_eq!(*recensus_calls.lock().unwrap(), 1);

        // No misses, no second census.
        read_family(
            ids(&["a"]),
            100,
            |_batch| async { Ok(vec![row("a", 1)]) },
            |r: &Row| r.id.clone(),
            || async { Err::<Vec<String>, _>(CallError::Timeout) },
        )
        .await
        .expect("no recensus needed");
    }
}
