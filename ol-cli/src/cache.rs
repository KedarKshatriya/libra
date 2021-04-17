//! `cache`
use std::sync::Mutex;
use rocksdb::DB;
use once_cell::sync::Lazy;

/// caching database name, to be appended to node_home
pub const MONITOR_DB_PATH: &str = "/tmp/0L/monitor_db";

/// Construct Lazy Database instance
pub static DB_CACHE: Lazy<DB> = Lazy::new(||{
    DB::open_default(MONITOR_DB_PATH).unwrap()
});


/// TODO: Use mutex instead of Lazy?
/// create a mutex of db
pub fn db_mutex() -> Mutex<DB> {
    let db = DB::open_default(MONITOR_DB_PATH).unwrap();
    Mutex::new(db)
}
