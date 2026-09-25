#!/usr/bin/env python3
"""Generate a dependency-free Xcode project. Run from any directory after adding sources."""
from pathlib import Path
import hashlib
import json
import plistlib

ROOT = Path(__file__).resolve().parents[1]
objects = {}

def ident(key):
    return hashlib.sha256(key.encode()).hexdigest()[:24].upper()

def add(key, value):
    ref = ident(key)
    objects[ref] = value
    return ref

def quote(value):
    return json.dumps(str(value))

def encode(value, depth=0):
    indent = "\t" * depth
    if isinstance(value, dict):
        return "{\n" + "\n".join(f"{indent}\t{quote(k)} = {encode(v, depth + 1)};" for k, v in value.items()) + "\n" + indent + "}"
    if isinstance(value, list):
        return "(\n" + "\n".join(f"{indent}\t{encode(x, depth + 1)}," for x in value) + "\n" + indent + ")" if value else "()"
    return quote(value)

def file(path, kind):
    return add("file:" + path, dict(isa="PBXFileReference", lastKnownFileType=kind, path=path, sourceTree="<group>"))

def phase(key, kind, files, **extra):
    return add(key, dict(isa=kind, buildActionMask="2147483647", files=files, runOnlyForDeploymentPostprocessing="0", **extra))

def config_list(name, settings):
    configs = []
    for mode in ["Debug", "Release"]:
        values = dict(settings)
        values.update(SWIFT_OPTIMIZATION_LEVEL="-Onone" if mode == "Debug" else "-O", DEBUG_INFORMATION_FORMAT="dwarf" if mode == "Debug" else "dwarf-with-dsym")
        if mode == "Debug":
            values.update(SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG", ENABLE_TESTABILITY="YES")
        configs.append(add(name + mode, dict(isa="XCBuildConfiguration", buildSettings=values, name=mode)))
    return add(name + "configurations", dict(isa="XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible="0", defaultConfigurationName="Release"))

project = ident("project")
package = add("package", dict(isa="XCLocalSwiftPackageReference", relativePath="."))
product = add("core-product", dict(isa="XCSwiftPackageProductDependency", package=package, productName="LedgerCore"))
groups, products, targets = [], [], []
common = dict(SWIFT_VERSION="6.0", IPHONEOS_DEPLOYMENT_TARGET="26.0", SDKROOT="iphoneos", TARGETED_DEVICE_FAMILY="1,2",
              CODE_SIGN_STYLE="Automatic", CURRENT_PROJECT_VERSION="1", MARKETING_VERSION="0.1.0",
              SWIFT_STRICT_CONCURRENCY="complete", GENERATE_INFOPLIST_FILE="NO", PRODUCT_NAME="$(TARGET_NAME)",
              LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks"], SUPPORTS_MACCATALYST="NO")

for name, extension, product_type in [("LocalLedger", "app", "com.apple.product-type.application"),
                                      ("LocalLedgerWidget", "appex", "com.apple.product-type.app-extension"),
                                      ("LocalLedgerUITests", "xctest", "com.apple.product-type.bundle.ui-testing")]:
    refs, sources, resources = [], [], []
    for path in sorted((ROOT / name).rglob("*.swift")):
        relative = path.relative_to(ROOT).as_posix()
        ref = file(relative, "sourcecode.swift"); refs.append(ref)
        sources.append(add("build:" + relative, dict(isa="PBXBuildFile", fileRef=ref)))
    for path in [f"{name}/Assets.xcassets", f"{name}/PrivacyInfo.xcprivacy"]:
        if (ROOT / path).exists():
            ref = file(path, "folder.assetcatalog" if path.endswith("xcassets") else "text.xml"); refs.append(ref)
            resources.append(add("build:" + path, dict(isa="PBXBuildFile", fileRef=ref)))
    if (ROOT / name / "Info.plist").exists(): refs.append(file(f"{name}/Info.plist", "text.plist.xml"))
    groups.append(add("group:" + name, dict(isa="PBXGroup", children=refs, name=name, sourceTree="<group>")))
    output = add("product:" + name, dict(isa="PBXFileReference", explicitFileType={"app": "wrapper.application", "appex": "wrapper.app-extension", "xctest": "wrapper.cfbundle"}[extension], path=name + "." + extension, sourceTree="BUILT_PRODUCTS_DIR"))
    products.append(output)
    frameworks = [add("link-core", dict(isa="PBXBuildFile", productRef=product))] if name == "LocalLedger" else []
    phases = [phase(name + "sources", "PBXSourcesBuildPhase", sources), phase(name + "frameworks", "PBXFrameworksBuildPhase", frameworks), phase(name + "resources", "PBXResourcesBuildPhase", resources)]
    dependencies = []
    settings = dict(common, PRODUCT_BUNDLE_IDENTIFIER="dev.localledger.ios" + ("" if name == "LocalLedger" else ".widget" if extension == "appex" else ".uitests"), INFOPLIST_FILE=f"{name}/Info.plist")
    if name == "LocalLedger":
        settings.update(ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon", ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME="AccentColor", CODE_SIGN_ENTITLEMENTS="LocalLedger/LocalLedger.entitlements")
        embedded = add("embed-widget", dict(isa="PBXBuildFile", fileRef=ident("product:LocalLedgerWidget"), settings=dict(ATTRIBUTES=["RemoveHeadersOnCopy"])))
        phases.append(phase("embed-extensions", "PBXCopyFilesBuildPhase", [embedded], dstPath="", dstSubfolderSpec="13", name="Embed App Extensions"))
    if extension == "appex": settings.update(APPLICATION_EXTENSION_API_ONLY="YES", SKIP_INSTALL="YES", LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"])
    if extension == "xctest": settings.update(TEST_TARGET_NAME="LocalLedger", GENERATE_INFOPLIST_FILE="YES"); settings.pop("INFOPLIST_FILE")
    depends = "LocalLedgerWidget" if name == "LocalLedger" else "LocalLedger" if extension == "xctest" else None
    if depends:
        proxy = add(name + "proxy", dict(isa="PBXContainerItemProxy", containerPortal=project, proxyType="1", remoteGlobalIDString=ident("target:" + depends), remoteInfo=depends))
        dependencies.append(add(name + "dependency", dict(isa="PBXTargetDependency", target=ident("target:" + depends), targetProxy=proxy)))
    targets.append(add("target:" + name, dict(isa="PBXNativeTarget", buildConfigurationList=config_list(name, settings), buildPhases=phases,
        buildRules=[], dependencies=dependencies, name=name, productName=name, productReference=output, productType=product_type,
        packageProductDependencies=[product] if name == "LocalLedger" else [])))

products_group = add("products-group", dict(isa="PBXGroup", children=products, name="Products", sourceTree="<group>"))
root_group = add("root-group", dict(isa="PBXGroup", children=groups + [products_group], sourceTree="<group>"))
add("project", dict(isa="PBXProject", attributes=dict(BuildIndependentTargetsInParallel="YES", LastUpgradeCheck="2600"),
    buildConfigurationList=config_list("project", dict(CLANG_ENABLE_MODULES="YES", CLANG_ENABLE_OBJC_ARC="YES", SWIFT_VERSION="6.0", IPHONEOS_DEPLOYMENT_TARGET="26.0", SDKROOT="iphoneos")),
    compatibilityVersion="Xcode 15.0", developmentRegion="en", hasScannedForEncodings="0", knownRegions=["en", "Base"], mainGroup=root_group,
    productRefGroup=products_group, projectDirPath="", projectRoot="", targets=targets, packageReferences=[package]))
project_dir = ROOT / "LocalLedger.xcodeproj"
project_dir.mkdir(exist_ok=True)
content = "// !$*UTF8*$!\n" + encode(dict(archiveVersion="1", classes={}, objectVersion="60", objects=objects, rootObject=project)) + "\n"
(project_dir / "project.pbxproj").write_text(content)

def buildable(name):
    suffix = ".xctest" if name.endswith("UITests") else ".app"
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("target:" + name)}" BuildableName="{name}{suffix}" BlueprintName="{name}" ReferencedContainer="container:LocalLedger.xcodeproj"/>'

scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable("LocalLedger")}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{buildable("LocalLedgerUITests")}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable("LocalLedger")}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable("LocalLedger")}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
schemes = project_dir / "xcshareddata/xcschemes"; schemes.mkdir(parents=True, exist_ok=True)
(schemes / "LocalLedger.xcscheme").write_text(scheme)
print(f"Generated {project_dir} with {len(targets)} targets")
