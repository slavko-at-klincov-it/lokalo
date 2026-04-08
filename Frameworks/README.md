# llama.xcframework

The Lokalo app depends on the official `llama.xcframework` from
[ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp). It is **not**
checked in here because it weighs ~555 MB.

## Quick fetch

From the project root:

```bash
./scripts/fetch-llama-framework.sh
```

This script downloads and unzips the latest tagged release of `llama.cpp`
into `Frameworks/llama.xcframework`.

## Manual fetch

If you'd rather pin a specific version:

```bash
TAG=b8702
curl -L -o /tmp/llama.zip \
  "https://github.com/ggml-org/llama.cpp/releases/download/${TAG}/llama-${TAG}-xcframework.zip"
unzip -o /tmp/llama.zip -d Frameworks/
mv Frameworks/build-apple/llama.xcframework Frameworks/
rm -rf Frameworks/build-apple /tmp/llama.zip
```

After the framework is in place, regenerate the Xcode project with
`xcodegen generate` and build as normal.
