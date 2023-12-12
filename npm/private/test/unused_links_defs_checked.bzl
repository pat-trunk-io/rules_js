"@generated by @aspect_rules_js//npm/private:npm_import.bzl for npm package unused@0.2.2"

load("@aspect_rules_js//js:defs.bzl", _js_run_binary = "js_run_binary")
load("@aspect_rules_js//npm/private:npm_package_store_internal.bzl", _npm_package_store = "npm_package_store_internal")
load("@aspect_rules_js//npm/private:npm_link_package_store.bzl", _npm_link_package_store = "npm_link_package_store")
load("@aspect_rules_js//npm/private:npm_package_internal.bzl", _npm_package_internal = "npm_package_internal")
load("@aspect_rules_js//npm/private:utils.bzl", _utils = "utils")

# Generated npm_package_store targets for npm package unused@0.2.2
# buildifier: disable=function-docstring
def npm_imported_package_store(name):
    root_package = ""
    is_root = native.package_name() == root_package
    if not is_root:
        msg = "No store links in bazel package '%s' for npm package npm package unused@0.2.2. This is neither the root package nor a link package of this package." % native.package_name()
        fail(msg)
    if not name.endswith("/unused"):
        msg = "name must end with one of '/unused' when linking the store in package 'unused'; recommended value is 'node_modules/unused'"
        fail(msg)
    link_root_name = name[:-len("/unused")]

    deps = {
        ":.aspect_rules_js/{}/esprima@1.0.0/pkg".format(link_root_name): "esprima",
        ":.aspect_rules_js/{}/minimist@0.0.10/pkg".format(link_root_name): "minimist",
        ":.aspect_rules_js/{}/optimist@0.6.0/pkg".format(link_root_name): "optimist",
        ":.aspect_rules_js/{}/unused@0.2.2/pkg".format(link_root_name): "unused",
        ":.aspect_rules_js/{}/wordwrap@0.0.3/pkg".format(link_root_name): "wordwrap",
    }
    lc_deps = {
        ":.aspect_rules_js/{}/esprima@1.0.0/pkg".format(link_root_name): "esprima",
        ":.aspect_rules_js/{}/minimist@0.0.10/pkg".format(link_root_name): "minimist",
        ":.aspect_rules_js/{}/optimist@0.6.0/pkg".format(link_root_name): "optimist",
        ":.aspect_rules_js/{}/unused@0.2.2/pkg_pre_lc_lite".format(link_root_name): "unused",
        ":.aspect_rules_js/{}/wordwrap@0.0.3/pkg".format(link_root_name): "wordwrap",
    }
    ref_deps = {
        ":.aspect_rules_js/{}/esprima@1.0.0/ref".format(link_root_name): "esprima",
        ":.aspect_rules_js/{}/optimist@0.6.0/ref".format(link_root_name): "optimist",
    }

    has_lifecycle_build_target = False
    store_target_name = ".aspect_rules_js/{}/unused@0.2.2".format(link_root_name)

    # reference target used to avoid circular deps
    _npm_package_store(
        name = "{}/ref".format(store_target_name),
        package = "unused",
        version = "0.2.2",
        dev = True,
        tags = ["manual"],
        use_declare_symlink = select({
            "@aspect_rules_js//js:allow_unresolved_symlinks": True,
            "//conditions:default": False,
        }),
    )

    # post-lifecycle target with reference deps for use in terminal target with transitive closure
    _npm_package_store(
        name = "{}/pkg".format(store_target_name),
        src = "{}/pkg_lc".format(store_target_name) if has_lifecycle_build_target else "@npm//:npm__unused__0.2.2_source_directory",
        package = "unused",
        version = "0.2.2",
        dev = True,
        deps = ref_deps,
        tags = ["manual"],
        use_declare_symlink = select({
            "@aspect_rules_js//js:allow_unresolved_symlinks": True,
            "//conditions:default": False,
        }),
    )

    # virtual store target with transitive closure of all npm package dependencies
    _npm_package_store(
        name = store_target_name,
        src = None if True else "@npm//:npm__unused__0.2.2_source_directory",
        package = "unused",
        version = "0.2.2",
        dev = True,
        deps = deps,
        visibility = ["//visibility:public"],
        tags = ["manual"],
        use_declare_symlink = select({
            "@aspect_rules_js//js:allow_unresolved_symlinks": True,
            "//conditions:default": False,
        }),
    )

    # filegroup target that provides a single file which is
    # package directory for use in $(execpath) and $(rootpath)
    native.filegroup(
        name = "{}/dir".format(store_target_name),
        srcs = [":{}".format(store_target_name)],
        output_group = _utils.package_directory_output_group,
        visibility = ["//visibility:public"],
        tags = ["manual"],
    )

    if has_lifecycle_build_target:
        # pre-lifecycle target with reference deps for use terminal pre-lifecycle target
        _npm_package_store(
            name = "{}/pkg_pre_lc_lite".format(store_target_name),
            package = "unused",
            version = "0.2.2",
            dev = True,
            deps = ref_deps,
            tags = ["manual"],
            use_declare_symlink = select({
                "@aspect_rules_js//js:allow_unresolved_symlinks": True,
                "//conditions:default": False,
            }),
        )

        # terminal pre-lifecycle target for use in lifecycle build target below
        _npm_package_store(
            name = "{}/pkg_pre_lc".format(store_target_name),
            package = "unused",
            version = "0.2.2",
            dev = True,
            deps = lc_deps,
            tags = ["manual"],
            use_declare_symlink = select({
                "@aspect_rules_js//js:allow_unresolved_symlinks": True,
                "//conditions:default": False,
            }),
        )

        # lifecycle build action
        _js_run_binary(
            name = "{}/lc".format(store_target_name),
            srcs = [
                "@@npm__unused__0.2.2//:pkg",
                ":{}/pkg_pre_lc".format(store_target_name),
            ],
            # js_run_binary runs in the output dir; must add "../../../" because paths are relative to the exec root
            args = [
                       "unused",
                       "../../../$(execpath @@npm__unused__0.2.2//:pkg)",
                       "../../../$(@D)",
                   ] +
                   select({
                       "@aspect_rules_js//platforms/os:osx": ["--platform=darwin"],
                       "@aspect_rules_js//platforms/os:linux": ["--platform=linux"],
                       "@aspect_rules_js//platforms/os:windows": ["--platform=win32"],
                       "//conditions:default": [],
                   }) +
                   select({
                       "@aspect_rules_js//platforms/cpu:arm64": ["--arch=arm64"],
                       "@aspect_rules_js//platforms/cpu:x86_64": ["--arch=x64"],
                       "//conditions:default": [],
                   }) +
                   select({
                       "@aspect_rules_js//platforms/libc:glibc": ["--libc=glibc"],
                       "@aspect_rules_js//platforms/libc:musl": ["--libc=musl"],
                       "//conditions:default": [],
                   }),
            copy_srcs_to_bin = False,
            tool = "@aspect_rules_js//npm/private/lifecycle:lifecycle-hooks",
            out_dirs = ["node_modules/.aspect_rules_js/unused@0.2.2/node_modules/unused"],
            tags = ["manual"],
            execution_requirements = {
                "no-sandbox": "1",
            },
            mnemonic = "NpmLifecycleHook",
            progress_message = "Running lifecycle hooks on npm package unused@0.2.2",
            env = {},
        )

        # post-lifecycle npm_package
        _npm_package_internal(
            name = "{}/pkg_lc".format(store_target_name),
            src = ":{}/lc".format(store_target_name),
            package = "unused",
            version = "0.2.2",
            tags = ["manual"],
        )

# Generated npm_package_store and npm_link_package_store targets for npm package unused@0.2.2
# buildifier: disable=function-docstring
def npm_link_imported_package_store(name):
    link_packages = {
        "npm/private/test": ["unused"],
    }
    if native.package_name() in link_packages:
        link_aliases = link_packages[native.package_name()]
    else:
        link_aliases = ["unused"]

    link_alias = None
    for _link_alias in link_aliases:
        if name.endswith("/{}".format(_link_alias)):
            # longest match wins
            if not link_alias or len(_link_alias) > len(link_alias):
                link_alias = _link_alias
    if not link_alias:
        msg = "name must end with one of '/{{ {link_aliases_comma_separated} }}' when called from package 'unused'; recommended value(s) are 'node_modules/{{ {link_aliases_comma_separated} }}'".format(link_aliases_comma_separated = ", ".join(link_aliases))
        fail(msg)

    link_root_name = name[:-len("/{}".format(link_alias))]
    store_target_name = ".aspect_rules_js/{}/unused@0.2.2".format(link_root_name)

    # terminal package store target to link
    _npm_link_package_store(
        name = name,
        package = link_alias,
        src = "//:{}".format(store_target_name),
        visibility = ["//visibility:private"],
        tags = ["manual"],
        use_declare_symlink = select({
            "@aspect_rules_js//js:allow_unresolved_symlinks": True,
            "//conditions:default": False,
        }),
    )

    # filegroup target that provides a single file which is
    # package directory for use in $(execpath) and $(rootpath)
    native.filegroup(
        name = "{}/dir".format(name),
        srcs = [":{}".format(name)],
        output_group = _utils.package_directory_output_group,
        visibility = ["//visibility:private"],
        tags = ["manual"],
    )

    return [":{}".format(name)] if False else []

# Generated npm_package_store and npm_link_package_store targets for npm package unused@0.2.2
# buildifier: disable=function-docstring
def npm_link_imported_package(
        name = "node_modules",
        link = None,
        fail_if_no_link = True):
    root_package = ""
    link_packages = {
        "npm/private/test": ["unused"],
    }

    if link_packages and link != None:
        fail("link attribute cannot be specified when link_packages are set")

    is_link = (link == True) or (link == None and native.package_name() in link_packages)
    is_root = native.package_name() == root_package

    if fail_if_no_link and not is_root and not link:
        msg = "Nothing to link in bazel package '%s' for npm package npm package unused@0.2.2. This is neither the root package nor a link package of this package." % native.package_name()
        fail(msg)

    link_targets = []
    scoped_targets = {}

    if is_link:
        link_aliases = []
        if native.package_name() in link_packages:
            link_aliases = link_packages[native.package_name()]
        if not link_aliases:
            link_aliases = ["unused"]
        for link_alias in link_aliases:
            link_target_name = "{}/{}".format(name, link_alias)
            npm_link_imported_package_store(name = link_target_name)
            if False:
                link_targets.append(":{}".format(link_target_name))
                if len(link_alias.split("/", 1)) > 1:
                    link_scope = link_alias.split("/", 1)[0]
                    if link_scope not in scoped_targets:
                        scoped_targets[link_scope] = []
                    scoped_targets[link_scope].append(link_target_name)

    if is_root:
        npm_imported_package_store("{}/unused".format(name))

    return (link_targets, scoped_targets)
