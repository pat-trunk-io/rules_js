"""Starlark generation helpers for npm_translate_lock.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(":utils.bzl", "utils")
load(":npm_translate_lock_helpers.bzl", "helpers")
load(":starlark_codegen_utils.bzl", "starlark_codegen_utils")

################################################################################
_NPM_IMPORT_TMPL = \
    """    npm_import(
        name = "{name}",
        root_package = "{root_package}",
        link_workspace = "{link_workspace}",
        link_packages = {link_packages},
        package = "{package}",
        version = "{version}",
        url = "{url}",
        package_visibility = {package_visibility},{maybe_dev}{maybe_commit}{maybe_generate_bzl_library_targets}{maybe_integrity}{maybe_deps}{maybe_transitive_closure}{maybe_patches}{maybe_patch_args}{maybe_lifecycle_hooks}{maybe_custom_postinstall}{maybe_lifecycle_hooks_env}{maybe_lifecycle_hooks_execution_requirements}{maybe_bins}{maybe_npm_auth}{maybe_npm_auth_basic}{maybe_npm_auth_username}{maybe_npm_auth_password}{maybe_replace_package}{maybe_lifecycle_hooks_use_default_shell_env}
    )
"""

_BIN_TMPL = \
    """load("{repo_package_json_bzl}", _bin = "bin", _bin_factory = "bin_factory")
bin = _bin
bin_factory = _bin_factory
"""

_FP_STORE_TMPL = \
    """
    if is_root:
        _npm_package_store(
            name = "{virtual_store_root}/{{}}/{virtual_store_name}".format(name),
            src = "{npm_package_target}",
            package = "{package}",
            version = "0.0.0",
            deps = {deps},
            visibility = ["//visibility:public"],
            tags = ["manual"],
            use_declare_symlink = select({{
                "@aspect_rules_js//js:allow_unresolved_symlinks": True,
                "//conditions:default": False,
            }}),
        )"""

_FP_DIRECT_TMPL = \
    """
    for link_package in {link_packages}:
        if link_package == native.package_name():
            # terminal target for direct dependencies
            _npm_link_package_store(
                name = "{{}}/{name}".format(name),
                src = "//{root_package}:{virtual_store_root}/{{}}/{virtual_store_name}".format(name),
                visibility = {link_visibility},
                tags = ["manual"],
                use_declare_symlink = select({{
                    "@aspect_rules_js//js:allow_unresolved_symlinks": True,
                    "//conditions:default": False,
                }}),{maybe_bins}
            )

            # filegroup target that provides a single file which is
            # package directory for use in $(execpath) and $(rootpath)
            native.filegroup(
                name = "{{}}/{name}/dir".format(name),
                srcs = [":{{}}/{name}".format(name)],
                output_group = "{package_directory_output_group}",
                visibility = {link_visibility},
                tags = ["manual"],
            )"""

_FP_DIRECT_TARGET_TMPL = \
    """
    for link_package in {link_packages}:
        if link_package == bazel_package:
            link_targets.append("//{{}}:{{}}/{name}".format(bazel_package, name))"""

_BZL_LIBRARY_TMPL = \
    """bzl_library(
    name = "{name}_bzl_library",
    srcs = ["{src}"],
    deps = ["{dep}"],
    visibility = ["//visibility:public"],
)
"""

_PACKAGE_JSON_BZL_FILENAME = "package_json.bzl"
_RESOLVED_JSON_FILENAME = "resolved.json"

# buildifier: disable=function-docstring
def generate_repository_files(rctx, pnpm_lock_label, importers, packages, patched_dependencies, root_package, default_registry, npm_registries, npm_auth, link_workspace):
    # empty line after bzl docstring since buildifier expects this if this file is vendored in
    generated_by_prefix = "\"\"\"@generated by npm_translate_lock(name = \"{}\", pnpm_lock = \"{}\")\"\"\"\n".format(helpers.to_apparent_repo_name(rctx.name), utils.consistent_label_str(pnpm_lock_label))

    npm_imports = helpers.get_npm_imports(importers, packages, patched_dependencies, root_package, rctx.name, rctx.attr, rctx.attr.lifecycle_hooks, rctx.attr.lifecycle_hooks_execution_requirements, rctx.attr.lifecycle_hooks_use_default_shell_env, npm_registries, default_registry, npm_auth)

    link_packages = [helpers.link_package(root_package, import_path) for import_path in importers.keys()]

    defs_bzl_header = ["""# buildifier: disable=bzl-visibility
load("@aspect_rules_js//js:defs.bzl", _js_library = "js_library")"""]

    fp_links = {}
    rctx_files = {
        "BUILD.bazel": [
            """load("@bazel_skylib//:bzl_library.bzl", "bzl_library")""",
            "",
            """
# A no-op run target that can be run to invalidate the repository
# to update the pnpm lockfile. Useful under bzlmod where
# `bazel sync --only=repo` is a no-op.
sh_binary(
    name = "sync",
    srcs = ["@aspect_rules_js//npm/private:noop.sh"],
)""",
            "",
            "exports_files({})".format(starlark_codegen_utils.to_list_attr([
                rctx.attr.defs_bzl_filename,
                rctx.attr.repositories_bzl_filename,
            ])),
        ],
    }

    # Look for first-party file: links in packages
    for package_info in packages.values():
        name = package_info.get("name")
        version = package_info.get("version")
        deps = package_info.get("dependencies")
        if version.startswith("file:"):
            if version in packages and packages[version]["id"]:
                dep_path = helpers.link_package(root_package, packages[version]["id"][len("file:"):])
            else:
                dep_path = helpers.link_package(root_package, version[len("file:"):])
            dep_key = "{}+{}".format(name, version)
            transitive_deps = {}
            for raw_package, raw_version in deps.items():
                store_package, store_version = utils.parse_pnpm_package_key(raw_package, raw_version)
                dep_store_target = """"//{root_package}:{virtual_store_root}/{{}}/{virtual_store_name}".format(name)""".format(
                    root_package = root_package,
                    virtual_store_name = utils.virtual_store_name(store_package, store_version),
                    virtual_store_root = utils.virtual_store_root,
                )
                if dep_store_target not in transitive_deps:
                    transitive_deps[dep_store_target] = [raw_package]
                else:
                    transitive_deps[dep_store_target].append(raw_package)

            # collapse link aliases lists into to acomma separated strings
            for dep_store_target in transitive_deps.keys():
                transitive_deps[dep_store_target] = ",".join(transitive_deps[dep_store_target])
            fp_links[dep_key] = {
                "package": name,
                "path": dep_path,
                "link_packages": {},
                "deps": transitive_deps,
            }

    # Look for first-party links in importers
    for import_path, importer in importers.items():
        dependencies = importer.get("all_deps")
        if type(dependencies) != "dict":
            msg = "expected dict of dependencies in processed importer '{}'".format(import_path)
            fail(msg)
        link_package = helpers.link_package(root_package, import_path)
        for dep_package, dep_version in dependencies.items():
            if dep_version.startswith("file:"):
                if dep_version in packages and packages[dep_version]["id"]:
                    dep_path = helpers.link_package(root_package, packages[dep_version]["id"][len("file:"):])
                else:
                    dep_path = helpers.link_package(root_package, dep_version[len("file:"):])
                dep_key = "{}+{}".format(dep_package, dep_version)
                if not dep_key in fp_links.keys():
                    msg = "Expected to file: referenced package {} in first-party links".format(dep_key)
                    fail(msg)
                fp_links[dep_key]["link_packages"][link_package] = []
            elif dep_version.startswith("link:"):
                dep_importer = paths.normalize(paths.join(import_path, dep_version[len("link:"):]))
                dep_path = helpers.link_package(root_package, import_path, dep_version[len("link:"):])
                dep_key = "{}+{}".format(dep_package, dep_path)
                if dep_key in fp_links.keys():
                    fp_links[dep_key]["link_packages"][link_package] = []
                else:
                    transitive_deps = {}
                    raw_deps = {}
                    if dep_importer in importers.keys():
                        raw_deps = importers.get(dep_importer).get("deps")
                    for raw_package, raw_version in raw_deps.items():
                        store_package, store_version = utils.parse_pnpm_package_key(raw_package, raw_version)
                        dep_store_target = """"//{root_package}:{virtual_store_root}/{{}}/{virtual_store_name}".format(name)""".format(
                            root_package = root_package,
                            virtual_store_name = utils.virtual_store_name(store_package, store_version),
                            virtual_store_root = utils.virtual_store_root,
                        )
                        if dep_store_target not in transitive_deps:
                            transitive_deps[dep_store_target] = [raw_package]
                        else:
                            transitive_deps[dep_store_target].append(raw_package)

                    # collapse link aliases lists into to a comma separated strings
                    for dep_store_target in transitive_deps.keys():
                        transitive_deps[dep_store_target] = ",".join(transitive_deps[dep_store_target])
                    fp_links[dep_key] = {
                        "package": dep_package,
                        "path": dep_path,
                        "link_packages": {link_package: []},
                        "deps": transitive_deps,
                        "bins": importers.get(dep_path, {}).get("bins", {}),
                    }

    if fp_links:
        defs_bzl_header.append("""load("@aspect_rules_js//npm/private:npm_link_package_store.bzl", _npm_link_package_store = "npm_link_package_store")
load("@aspect_rules_js//npm/private:npm_package_store.bzl", _npm_package_store = "npm_package_store")""")

    npm_link_packages_const = """_LINK_PACKAGES = {link_packages}""".format(link_packages = str(link_packages))

    npm_link_targets_bzl = [
        """\
# buildifier: disable=function-docstring
def npm_link_targets(name = "node_modules", package = None):
    bazel_package = package if package != None else native.package_name()
    link = bazel_package in _LINK_PACKAGES

    link_targets = []
""",
    ]

    npm_link_all_packages_bzl = [
        """\
# buildifier: disable=function-docstring
def npm_link_all_packages(name = "node_modules", imported_links = []):
    root_package = "{root_package}"
    bazel_package = native.package_name()
    is_root = bazel_package == root_package
    link = bazel_package in _LINK_PACKAGES
    if not is_root and not link:
        msg = "The npm_link_all_packages() macro loaded from {defs_bzl_file} and called in bazel package '%s' may only be called in bazel packages that correspond to the pnpm root package or pnpm workspace projects. Projects are discovered from the pnpm-lock.yaml and may be missing if the lockfile is out of date. Root package: '{root_package}', pnpm workspace projects: %s" % (native.package_name(), {link_packages_comma_separated})
        fail(msg)
    link_targets = []
    scope_targets = {{}}

    for link_fn in imported_links:
        new_link_targets, new_scope_targets = link_fn(name)
        link_targets.extend(new_link_targets)
        for _scope, _targets in new_scope_targets.items():
            scope_targets[_scope] = scope_targets[_scope] + _targets if _scope in scope_targets else _targets
""".format(
            defs_bzl_file = "@{}//:{}".format(rctx.name, rctx.attr.defs_bzl_filename),
            link_packages_comma_separated = "\"'\" + \"', '\".join(_LINK_PACKAGES) + \"'\"" if len(link_packages) else "",
            root_package = root_package,
            pnpm_lock_label = pnpm_lock_label,
        ),
    ]

    # check all links and fail if there are duplicates which can happen with public hoisting
    helpers.check_for_conflicting_public_links(npm_imports, rctx.attr.public_hoist_packages)

    repositories_bzl = []

    if len(npm_imports) > 0:
        repositories_bzl.append("""load("@aspect_rules_js//npm:repositories.bzl", "npm_import")""")
        repositories_bzl.append("")

    repositories_bzl.append("# Generated npm_import repository rules corresponding to npm packages in {}".format(utils.consistent_label_str(pnpm_lock_label)))
    repositories_bzl.append("# buildifier: disable=function-docstring")
    repositories_bzl.append("def npm_repositories():")
    if len(npm_imports) == 0:
        repositories_bzl.append("    pass")
        repositories_bzl.append("")

    stores_bzl = []
    links_bzl = {}
    links_targets_bzl = {}
    for (i, _import) in enumerate(npm_imports):
        repositories_bzl.append(_gen_npm_import(rctx, _import, link_workspace))

        if _import.link_packages:
            defs_bzl_header.append(
                """load("{at}{repo_name}{links_repo_suffix}//:defs.bzl", link_{i} = "npm_link_imported_package_store", store_{i} = "npm_imported_package_store")""".format(
                    at = "@@" if utils.bzlmod_supported else "@",
                    i = i,
                    links_repo_suffix = utils.links_repo_suffix,
                    repo_name = _import.name,
                ),
            )
        else:
            defs_bzl_header.append(
                """load("{at}{repo_name}{links_repo_suffix}//:defs.bzl", store_{i} = "npm_imported_package_store")""".format(
                    at = "@@" if utils.bzlmod_supported else "@",
                    i = i,
                    links_repo_suffix = utils.links_repo_suffix,
                    repo_name = _import.name,
                ),
            )

        stores_bzl.append("""        store_{i}(name = "{{}}/{name}".format(name))""".format(
            i = i,
            name = _import.package,
        ))
        for link_package, _link_aliases in _import.link_packages.items():
            link_aliases = _link_aliases or [_import.package]
            for link_alias in link_aliases:
                if link_package not in links_bzl:
                    links_bzl[link_package] = []
                if link_package not in links_targets_bzl:
                    links_targets_bzl[link_package] = []
                links_bzl[link_package].append("""            link_{i}(name = "{{}}/{name}".format(name))""".format(
                    i = i,
                    name = link_alias,
                ))
                if "//visibility:public" in _import.package_visibility:
                    add_to_link_targets = """            link_targets.append("//{{}}:{{}}/{name}".format(bazel_package, name))""".format(name = link_alias)
                    links_bzl[link_package].append(add_to_link_targets)
                    links_targets_bzl[link_package].append(add_to_link_targets)
                    if len(link_alias.split("/", 1)) > 1:
                        package_scope = link_alias.split("/", 1)[0]
                        add_to_scoped_targets = """            scope_targets["{package_scope}"] = scope_targets["{package_scope}"] + [link_targets[-1]] if "{package_scope}" in scope_targets else [link_targets[-1]]""".format(package_scope = package_scope)
                        links_bzl[link_package].append(add_to_scoped_targets)
        for link_package in _import.link_packages.keys():
            build_file = paths.normalize(paths.join(link_package, "BUILD.bazel"))
            if build_file not in rctx_files:
                rctx_files[build_file] = []
            resolved_json_file_path = paths.normalize(paths.join(link_package, _import.package, _RESOLVED_JSON_FILENAME))
            rctx.file(resolved_json_file_path, json.encode({
                # Allow consumers to auto-detect this filetype
                "$schema": "https://docs.aspect.build/rules/aspect_rules_js/docs/npm_translate_lock",
                "version": _import.version,
                "integrity": _import.integrity,
            }))
            rctx_files[build_file].append("exports_files([\"{}\"])".format(resolved_json_file_path))
            if _import.package_info.get("has_bin"):
                if rctx.attr.generate_bzl_library_targets:
                    rctx_files[build_file].append("""load("@bazel_skylib//:bzl_library.bzl", "bzl_library")""")
                    rctx_files[build_file].append(_BZL_LIBRARY_TMPL.format(
                        name = _import.package,
                        src = ":" + paths.join(_import.package, _PACKAGE_JSON_BZL_FILENAME),
                        dep = "@{repo_name}//{link_package}:{package_name}_bzl_library".format(
                            repo_name = helpers.to_apparent_repo_name(_import.name),
                            link_package = link_package,
                            package_name = link_package.split("/")[-1] or _import.package.split("/")[-1],
                        ),
                    ))
                package_json_bzl_file_path = paths.normalize(paths.join(link_package, _import.package, _PACKAGE_JSON_BZL_FILENAME))
                repo_package_json_bzl = "{at}{repo_name}//{link_package}:{package_json_bzl}".format(
                    at = "@@" if utils.bzlmod_supported else "@",
                    repo_name = _import.name,
                    link_package = link_package,
                    package_json_bzl = _PACKAGE_JSON_BZL_FILENAME,
                )
                rctx.file(
                    package_json_bzl_file_path,
                    _BIN_TMPL.format(
                        repo_package_json_bzl = repo_package_json_bzl,
                    ),
                )

    if len(stores_bzl) > 0:
        npm_link_all_packages_bzl.append("""    if is_root:""")
        npm_link_all_packages_bzl.extend(stores_bzl)

    if len(links_bzl) > 0:
        npm_link_all_packages_bzl.append("""    if link:""")
        first_link = True
        for link_package, bzl in links_bzl.items():
            npm_link_all_packages_bzl.append("""        {els}if bazel_package == "{pkg}":""".format(
                els = "" if first_link else "el",
                pkg = link_package,
            ))
            npm_link_all_packages_bzl.extend(bzl)
            first_link = False

    if len(links_targets_bzl) > 0:
        npm_link_targets_bzl.append("""    if link:""")
        first_link = True
        for link_package, bzl in links_targets_bzl.items():
            npm_link_targets_bzl.append("""        {els}if bazel_package == "{pkg}":""".format(
                els = "" if first_link else "el",
                pkg = link_package,
            ))
            npm_link_targets_bzl.extend(bzl)
            first_link = False

    for fp_link in fp_links.values():
        fp_package = fp_link.get("package")
        fp_bins = fp_link.get("bins")
        fp_path = fp_link.get("path")
        fp_link_packages = fp_link.get("link_packages").keys()
        fp_deps = fp_link.get("deps")
        fp_bazel_name = utils.bazel_name(fp_package, fp_path)
        fp_target = "//{}:{}".format(
            fp_path,
            rctx.attr.npm_package_target_name.replace("{dirname}", paths.basename(fp_path)),
        )

        npm_link_all_packages_bzl.append(_FP_STORE_TMPL.format(
            bazel_name = fp_bazel_name,
            deps = starlark_codegen_utils.to_dict_attr(fp_deps, 3, quote_key = False),
            npm_package_target = fp_target,
            package = fp_package,
            virtual_store_name = utils.virtual_store_name(fp_package, "0.0.0"),
            virtual_store_root = utils.virtual_store_root,
        ))

        package_visibility, _ = helpers.gather_values_from_matching_names(True, rctx.attr.package_visibility, "*", fp_package)
        if len(package_visibility) == 0:
            package_visibility = ["//visibility:public"]

        if len(fp_link_packages) > 0:
            npm_link_all_packages_bzl.append(_FP_DIRECT_TMPL.format(
                bazel_name = fp_bazel_name,
                link_packages = fp_link_packages,
                link_visibility = package_visibility,
                name = fp_package,
                package_directory_output_group = utils.package_directory_output_group,
                root_package = root_package,
                virtual_store_name = utils.virtual_store_name(fp_package, "0.0.0"),
                virtual_store_root = utils.virtual_store_root,
                maybe_bins = ("""
                bins = %s,""" % starlark_codegen_utils.to_dict_attr(fp_bins, 4)) if len(fp_bins) > 0 else "",
            ))

            npm_link_targets_bzl.append(_FP_DIRECT_TARGET_TMPL.format(
                link_packages = fp_link_packages,
                name = fp_package,
            ))

            if "//visibility:public" in package_visibility:
                add_to_link_targets = """            link_targets.append(":{{}}/{name}".format(name))""".format(name = fp_package)
                npm_link_all_packages_bzl.append(add_to_link_targets)
                if len(fp_package.split("/", 1)) > 1:
                    package_scope = fp_package.split("/", 1)[0]
                    add_to_scoped_targets = """            scope_targets["{package_scope}"] = scope_targets["{package_scope}"] + [link_targets[-1]] if "{package_scope}" in scope_targets else [link_targets[-1]]""".format(
                        package_scope = package_scope,
                    )
                    npm_link_all_packages_bzl.append(add_to_scoped_targets)

    # Generate catch all & scoped npm_linked_packages target
    npm_link_all_packages_bzl.append("""
    for scope, scoped_targets in scope_targets.items():
        _js_library(
            name = "{}/{}".format(name, scope),
            srcs = scoped_targets,
            tags = ["manual"],
            visibility = ["//visibility:public"],
        )

    _js_library(
        name = name,
        srcs = link_targets,
        tags = ["manual"],
        visibility = ["//visibility:public"],
    )""")

    npm_link_targets_bzl.append("""    return link_targets""")

    rctx_files[rctx.attr.defs_bzl_filename] = [
        "\n".join(defs_bzl_header),
        "",
        npm_link_packages_const,
        "",
        "\n".join(npm_link_all_packages_bzl),
        "",
        "\n".join(npm_link_targets_bzl),
        "",
    ]
    rctx_files[rctx.attr.repositories_bzl_filename] = repositories_bzl

    for filename, contents in rctx.attr.additional_file_contents.items():
        if not filename in rctx_files.keys():
            rctx_files[filename] = contents
        elif filename.endswith(".bzl"):
            # bzl files are special cased since all load statements must go at the top
            load_statements = []
            other_statements = []
            for content in contents:
                if content.startswith("load("):
                    load_statements.append(content)
                else:
                    other_statements.append(content)
            rctx_files[filename] = load_statements + rctx_files[filename] + other_statements
        else:
            rctx_files[filename].extend(contents)

    for filename, contents in rctx_files.items():
        rctx.file(filename, generated_by_prefix + "\n" + "\n".join(contents))

def _gen_npm_import(rctx, _import, link_workspace):
    maybe_integrity = ("""
        integrity = "%s",""" % _import.integrity) if _import.integrity else ""
    maybe_deps = ("""
        deps = %s,""" % starlark_codegen_utils.to_dict_attr(_import.deps, 2)) if len(_import.deps) > 0 else ""
    maybe_transitive_closure = ("""
        transitive_closure = %s,""" % starlark_codegen_utils.to_dict_list_attr(_import.transitive_closure, 2)) if len(_import.transitive_closure) > 0 else ""
    maybe_patches = ("""
        patches = %s,""" % _import.patches) if len(_import.patches) > 0 else ""
    maybe_patch_args = ("""
        patch_args = %s,""" % _import.patch_args) if len(_import.patches) > 0 and len(_import.patch_args) > 0 else ""
    maybe_custom_postinstall = ("""
        custom_postinstall = \"%s\",""" % _import.custom_postinstall) if _import.custom_postinstall else ""
    maybe_lifecycle_hooks = ("""
        lifecycle_hooks = %s,""" % _import.lifecycle_hooks) if _import.run_lifecycle_hooks and _import.lifecycle_hooks else ""
    maybe_lifecycle_hooks_env = ("""
        lifecycle_hooks_env = %s,""" % _import.lifecycle_hooks_env) if _import.run_lifecycle_hooks and _import.lifecycle_hooks_env else ""
    maybe_lifecycle_hooks_execution_requirements = ("""
        lifecycle_hooks_execution_requirements = %s,""" % _import.lifecycle_hooks_execution_requirements) if _import.run_lifecycle_hooks else ""
    maybe_lifecycle_hooks_use_default_shell_env = ("""
        lifecycle_hooks_use_default_shell_env = True,""") if _import.lifecycle_hooks_use_default_shell_env else ""
    maybe_bins = ("""
        bins = %s,""" % starlark_codegen_utils.to_dict_attr(_import.bins, 2)) if len(_import.bins) > 0 else ""
    maybe_generate_bzl_library_targets = ("""
        generate_bzl_library_targets = True,""") if rctx.attr.generate_bzl_library_targets else ""
    maybe_commit = ("""
        commit = "%s",""" % _import.commit) if _import.commit else ""
    maybe_npm_auth = ("""
        npm_auth = "%s",""" % _import.npm_auth) if _import.npm_auth else ""
    maybe_npm_auth_basic = ("""
        npm_auth_basic = "%s",""" % _import.npm_auth_basic) if _import.npm_auth_basic else ""
    maybe_npm_auth_username = ("""
        npm_auth_username = "%s",""" % _import.npm_auth_username) if _import.npm_auth_username else ""
    maybe_npm_auth_password = ("""
        npm_auth_password = "%s",""" % _import.npm_auth_password) if _import.npm_auth_password else ""
    maybe_dev = ("""
        dev = True,""") if _import.dev else ""
    maybe_replace_package = ("""
        replace_package = "%s",""" % _import.replace_package) if _import.replace_package else ""

    return _NPM_IMPORT_TMPL.format(
        link_packages = starlark_codegen_utils.to_dict_attr(_import.link_packages, 2, quote_value = False),
        link_workspace = link_workspace,
        maybe_bins = maybe_bins,
        maybe_commit = maybe_commit,
        maybe_custom_postinstall = maybe_custom_postinstall,
        maybe_deps = maybe_deps,
        maybe_dev = maybe_dev,
        maybe_generate_bzl_library_targets = maybe_generate_bzl_library_targets,
        maybe_integrity = maybe_integrity,
        maybe_lifecycle_hooks = maybe_lifecycle_hooks,
        maybe_lifecycle_hooks_env = maybe_lifecycle_hooks_env,
        maybe_lifecycle_hooks_execution_requirements = maybe_lifecycle_hooks_execution_requirements,
        maybe_lifecycle_hooks_use_default_shell_env = maybe_lifecycle_hooks_use_default_shell_env,
        maybe_npm_auth = maybe_npm_auth,
        maybe_npm_auth_basic = maybe_npm_auth_basic,
        maybe_npm_auth_password = maybe_npm_auth_password,
        maybe_npm_auth_username = maybe_npm_auth_username,
        maybe_patch_args = maybe_patch_args,
        maybe_patches = maybe_patches,
        maybe_replace_package = maybe_replace_package,
        maybe_transitive_closure = maybe_transitive_closure,
        name = helpers.to_apparent_repo_name(_import.name),
        package = _import.package,
        package_visibility = _import.package_visibility,
        root_package = _import.root_package,
        url = _import.url,
        version = _import.version,
    )
