fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios build

```sh
[bundle exec] fastlane ios build
```

Build for App Store

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Upload to TestFlight

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload metadata and screenshots only

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Upload screenshots only

### ios release

```sh
[bundle exec] fastlane ios release
```

Submit to App Store review

### ios submit

```sh
[bundle exec] fastlane ios submit
```

Submit for review only (no build, no upload)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
