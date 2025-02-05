#!/usr/bin/env sh

set -ex

mode=release
release_flag=--release
package=leaf-ffi
name=leaf
lib=lib$name.a

# The script is assumed to run in the root of the workspace
base=$(dirname "$0")

# Debug or release build?
if [ "$1" = "debug" ]; then
	mode=debug
	release_flag=
fi

export IPHONEOS_DEPLOYMENT_TARGET=10.0
export MACOSX_DEPLOYMENT_TARGET=10.12

# Add Rust targets for Mac Catalyst only
rustup target add x86_64-apple-ios-macabi
rustup target add aarch64-apple-ios-macabi

# Build only for Mac Catalyst
cargo build -p $package $release_flag --no-default-features --features "default-aws-lc outbound-quic" --target x86_64-apple-ios-macabi
cargo build -p $package $release_flag --no-default-features --features "default-aws-lc outbound-quic" --target aarch64-apple-ios-macabi

cargo install --force cbindgen

# Directories to put the libraries.
rm -rf target/apple/$mode
mkdir -p target/apple/$mode/include
mkdir -p target/apple/$mode/maccatalyst

# Create a universal binary for Mac Catalyst
lipo -create \
    -arch x86_64 target/x86_64-apple-ios-macabi/$mode/$lib \
    -arch arm64 target/aarch64-apple-ios-macabi/$mode/$lib \
    -output target/apple/$mode/maccatalyst/$lib

# Generate the header file
cbindgen \
	--config $package/cbindgen.toml \
	$package/src/lib.rs > target/apple/$mode/include/$name.h

wd="$base/../target/apple/$mode"

# Remove existing artifact
rm -rf "$wd/$name.xcframework"

# A modulemap is required for Swift compatibility
cat << EOF > "$wd/include/module.modulemap"
module $name {
    header "$name.h"
    export *
}
EOF

# Create the XCFramework for Mac Catalyst only
xcodebuild -create-xcframework \
	-library "$wd/maccatalyst/$lib" -headers "$wd/include" \
	-output "$wd/$name.xcframework"

ls $wd/$name.xcframework
