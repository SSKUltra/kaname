//! Pinned UniFFI bindings generator.
//!
//! Building this with `--features cli` guarantees the generator version matches the
//! exact `uniffi` dependency, so `make core-xcframework` produces reproducible Swift
//! bindings. This binary is never compiled into the shipped library.

fn main() {
    uniffi::uniffi_bindgen_main()
}
