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

# Add Rust targets (including Mac Catalyst)
rustup target add x86_64-apple-darwin
rustup target add aarch64-apple-darwin
rustup target add aarch64-apple-ios
rustup target add x86_64-apple-ios
rustup target add aarch64-apple-ios-sim
rustup target add x86_64-apple-ios-macabi
rustup target add aarch64-apple-ios-macabi

# Build for each target
cargo build -p $package $release_flag --no-default-features --features "default-aws-lc outbound-quic" --target x86_64-apple-darwin
cargo build -p $package $release_flag --no-default-features --features "default-aws-lc outbound-quic" --target aarch64-apple-darwin
cargo build -p $package $release_flag --no-default-features --features "default-aws-lc outbound-quic" --target aarch64-apple-ios
cargo build -p $package $release_flag --no-default-features --features "default-aws-lc outbound-quic" --target x86_64-apple-ios
cargo build -p $package $release_flag --no-default-features --features "default-aws-lc outbound-quic" --target aarch64-apple-ios-sim
cargo build -p $package $release_flag --no-default-features --features "default-aws-lc outbound-quic" --target x86_64-apple-ios-macabi
cargo build -p $package $release_flag --no-default-features --features "default-aws-lc outbound-quic" --target aarch64-apple-ios-macabi

cargo install --force cbindgen

# Directories to put the libraries.
rm -rf target/apple/$mode
mkdir -p target/apple/$mode/include
mkdir -p target/apple/$mode/ios
mkdir -p target/apple/$mode/ios-sim
mkdir -p target/apple/$mode/macos
mkdir -p target/apple/$mode/maccatalyst

# Copy built libraries
cp target/aarch64-apple-ios/$mode/$lib target/apple/$mode/ios/
lipo -create \
	-arch x86_64 target/x86_64-apple-ios/$mode/$lib \
	-arch arm64 target/aarch64-apple-ios-sim/$mode/$lib \
	-output target/apple/$mode/ios-sim/$lib

lipo -create \
	-arch x86_64 target/x86_64-apple-darwin/$mode/$lib \
	-arch arm64 target/aarch64-apple-darwin/$mode/$lib \
	-output target/apple/$mode/macos/$lib

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

# Create the XCFramework including Mac Catalyst
xcodebuild -create-xcframework \
	-library "$wd/ios/$lib" -headers "$wd/include" \
	-library "$wd/ios-sim/$lib" -headers "$wd/include" \
	-library "$wd/macos/$lib" -headers "$wd/include" \
	-library "$wd/maccatalyst/$lib" -headers "$wd/include" \
	-output "$wd/$name.xcframework"

ls $wd/$name.xcframework
