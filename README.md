## Deprecated

This project has been deprecated and is no longer maintained.

Rationale: https://github.com/hexops/mach/issues/1166

## [OR IS IT?](https://www.youtube.com/watch?v=TN25ghkfgQA)

Since the deprecation of the Mach project while the status of Mach is unknown, we shall bring this project back to live because zgpu and zgui relies on a dawn binary built originally from one of the Mach repo.

## Requirement
Due to the deprecation of Mach,the dependency of using tool from Mach is decoupled due to the outdated and hard to update codebase (stopped at ~zig 0.10.x). We have replaced the build system natively to the original dawn requirement, so you will need the following tools to make it work for the current iteration:

- zig 0.15.1
- [python 3](https://www.python.org/) and [jinja2](https://stackoverflow.com/a/18983050/20840262)
- [cmake](https://cmake.org/)
- [ninja](https://ninja-build.org/)

To build the library, all you need is to run:

```
zig build
```

## To use as a dependency

If `webgpu_dawn` is the name of the dependency in your `build.zig.zon`:
```
try @import("webgpu_dawn").link(b, "webgpu_dawn", your_module);
```