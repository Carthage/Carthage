# `Cartfile` format

A `Cartfile` describes your project’s dependencies to Carthage, allowing it to
resolve and build them for you.

## Example

```
github "ReactiveCocoa/ReactiveCocoa" >= 2.3.1
github "Mantle/Mantle" ~> 1.0
github "jspahrsummers/xcconfigs"
```

This example describes three dependencies:

1. [ReactiveCocoa](https://github.com/ReactiveCocoa/ReactiveCocoa), of version 2.3.1 or later
1. [Mantle](https://github.com/Mantle/Mantle), of version 1.x (1.0 or later, but less than 2.0)
1. The latest version of [jspahrsummers/xcconfigs](http://github.com/jspahrsummers/xcconfigs)
