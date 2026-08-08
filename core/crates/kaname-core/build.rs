//! Build-time crypto-backend wiring for the SQLCipher-backed encrypted store.
//!
//! `rusqlite`'s `bundled-sqlcipher` feature compiles SQLCipher from source. Which crypto
//! provider it uses is chosen by `libsqlite3-sys` per target:
//!
//! * **Apple** (macOS host + `*-apple-ios*`): it auto-selects CommonCrypto
//!   (`SQLCIPHER_CRYPTO_CC`) and links `Security`/`CoreFoundation` itself — nothing to do
//!   here (the app target re-links `Security` via Tuist for the final static-lib link).
//! * **Every other target** (Linux/CI): it would default to OpenSSL and hard-code
//!   `-lcrypto`. The Constitution forbids OpenSSL anywhere near the free/core engine
//!   (Principle I; the privacy-egress audit denylists `openssl`/`openssl-sys`), so we
//!   instead force **LibTomCrypt** and keep OpenSSL entirely out of the link:
//!     1. the caller compiles the LibTomCrypt provider by setting
//!        `LIBSQLITE3_FLAGS=-DSQLCIPHER_CRYPTO_LIBTOMCRYPT` (Makefile / CI),
//!     2. we link LibTomCrypt here for the crypto symbols, and
//!     3. we shadow the `-lcrypto` that `libsqlite3-sys` still emits with an empty stub
//!        archive placed first on the link search path, so the reference resolves to
//!        nothing and **zero OpenSSL code is linked** (no `libssl-dev` need exist).

use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;

fn main() {
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();

    // Apple targets: libsqlite3-sys selects CommonCrypto and links the frameworks itself.
    if matches!(
        target_os.as_str(),
        "macos" | "ios" | "tvos" | "watchos" | "visionos"
    ) {
        return;
    }

    // Non-Apple (Linux/CI): SQLCipher is compiled against LibTomCrypt (see module docs).
    // LibTomCrypt supplies AES/SHA/HMAC/PBKDF2/Fortuna — no bignum, so `tomcrypt` alone.
    //
    // Emit it as a *trailing* linker argument rather than `cargo:rustc-link-lib`: the
    // SQLCipher object that references `find_cipher`/`find_hash`/… lives in the
    // `libsqlite3-sys` rlib, which the linker sees *after* build-script libraries, so a
    // normally-ordered `-ltomcrypt` is discarded (its symbols aren't needed yet at its
    // position). A trailing `-l` sits after every object that references it and resolves
    // cleanly (tomcrypt is on the default library search path).
    println!("cargo:rustc-link-arg=-ltomcrypt");

    // Defang the OpenSSL `-lcrypto` that libsqlite3-sys hard-codes on non-Apple: an empty
    // `libcrypto.a`, searched first, satisfies the reference with no OpenSSL bytes.
    let out_dir = env::var("OUT_DIR").expect("cargo sets OUT_DIR for build scripts");
    write_empty_archive(Path::new(&out_dir).join("libcrypto.a").as_path());
    println!("cargo:rustc-link-search=native={out_dir}");
}

/// Write a valid, empty `ar` static archive at `path` (satisfies a `-l` reference with no
/// object code). Uses the `ar` from the C toolchain the `cc` crate already relies on.
fn write_empty_archive(path: &Path) {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create OUT_DIR");
    }
    // Remove any stale archive so `ar` writes a fresh, empty one.
    let _ = fs::remove_file(path);
    let ar = env::var("AR").unwrap_or_else(|_| "ar".to_string());
    let status = Command::new(&ar)
        .arg("crs")
        .arg(path)
        .status()
        .unwrap_or_else(|e| panic!("failed to run `{ar}` to build the libcrypto stub: {e}"));
    assert!(
        status.success(),
        "`{ar} crs` failed to write the libcrypto stub"
    );
}
