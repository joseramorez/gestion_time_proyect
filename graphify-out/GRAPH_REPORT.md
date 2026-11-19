# Graph Report - .  (2026-11-12)

## Corpus Check
- Corpus is ~11,958 words - fits in a single context window. You may not need a graph.

## Summary
- 104 nodes · 116 edges · 15 communities (12 shown, 3 thin omitted)
- Extraction: 93% EXTRACTED · 7% INFERRED · 0% AMBIGUOUS · INFERRED: 8 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Linux Runner|Linux Runner]]
- [[_COMMUNITY_Win32 Window Base|Win32 Window Base]]
- [[_COMMUNITY_Flutter Demo App|Flutter Demo App]]
- [[_COMMUNITY_Windows Entry Point|Windows Entry Point]]
- [[_COMMUNITY_Window Class Registrar|Window Class Registrar]]
- [[_COMMUNITY_macOS Main Window|macOS Main Window]]
- [[_COMMUNITY_Windows Plugin Registration|Windows Plugin Registration]]
- [[_COMMUNITY_macOS Icon Assets|macOS Icon Assets]]
- [[_COMMUNITY_macOS AppDelegate|macOS AppDelegate]]
- [[_COMMUNITY_Widget Tests|Widget Tests]]
- [[_COMMUNITY_macOS Runner Tests|macOS Runner Tests]]
- [[_COMMUNITY_Flutter Export Env|Flutter Export Env]]

## God Nodes (most connected - your core abstractions)
1. `WindowClassRegistrar` - 7 edges
2. `Create()` - 7 edges
3. `Destroy()` - 7 edges
4. `MessageHandler()` - 5 edges
5. `AppDelegate` - 4 edges
6. `OnCreate()` - 4 edges
7. `WndProc()` - 4 edges
8. `GetClientArea()` - 4 edges
9. `_MyApplication` - 3 edges
10. `MainFlutterWindow` - 3 edges

## Surprising Connections (you probably didn't know these)
- `my_application_activate()` --calls--> `fl_register_plugins()`  [INFERRED]
  linux/runner/my_application.cc → linux/flutter/generated_plugin_registrant.cc
- `main()` --calls--> `my_application_new()`  [INFERRED]
  linux/runner/main.cc → linux/runner/my_application.cc
- `OnCreate()` --calls--> `RegisterPlugins()`  [INFERRED]
  windows/runner/flutter_window.cpp → windows/flutter/generated_plugin_registrant.cc
- `OnCreate()` --calls--> `GetClientArea()`  [INFERRED]
  windows/runner/flutter_window.cpp → windows/runner/win32_window.cpp
- `OnCreate()` --calls--> `SetChildContent()`  [INFERRED]
  windows/runner/flutter_window.cpp → windows/runner/win32_window.cpp

## Communities (15 total, 3 thin omitted)

### Community 0 - "Linux Runner"
Cohesion: 0.11
Nodes (7): fl_register_plugins(), main(), my_application_activate(), my_application_new(), _MyApplication, dart_entrypoint_arguments, parent_instance

### Community 1 - "Win32 Window Base"
Cohesion: 0.20
Nodes (13): Create(), Destroy(), EnableFullDpiSupportIfAvailable(), GetThisFromHandle(), GetWindowClass(), MessageHandler(), OnCreate(), OnDestroy() (+5 more)

### Community 2 - "Flutter Demo App"
Cohesion: 0.18
Nodes (10): build, _incrementCounter, main, MaterialApp, MyApp, MyHomePage, _MyHomePageState, Scaffold (+2 more)

### Community 4 - "Windows Entry Point"
Cohesion: 0.43
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

### Community 5 - "Window Class Registrar"
Cohesion: 0.29
Nodes (5): WindowClassRegistrar, class_registered_, GetWindowClass, instance_, UnregisterWindowClass

### Community 6 - "macOS Main Window"
Cohesion: 0.33
Nodes (3): RegisterGeneratedPlugins(), NSWindow, MainFlutterWindow

### Community 7 - "Windows Plugin Registration"
Cohesion: 0.40
Nodes (4): RegisterPlugins(), OnCreate(), GetClientArea(), SetChildContent()

### Community 8 - "macOS Icon Assets"
Cohesion: 0.40
Nodes (4): images, info, author, version

### Community 10 - "Widget Tests"
Cohesion: 0.40
Nodes (4): main, package:flutter_test/flutter_test.dart, package:gestion_time_proyect/main.dart, package:flutter/material.dart

## Knowledge Gaps
- **24 isolated node(s):** `MyApp`, `MyHomePage`, `_MyHomePageState`, `main`, `build` (+19 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `WindowClassRegistrar` connect `Window Class Registrar` to `Win32 Window Base`?**
  _High betweenness centrality (0.041) - this node is a cross-community bridge._
- **Why does `OnCreate()` connect `Windows Plugin Registration` to `Windows FlutterWindow`?**
  _High betweenness centrality (0.040) - this node is a cross-community bridge._
- **What connects `MyApp`, `MyHomePage`, `_MyHomePageState` to the rest of the system?**
  _24 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Linux Runner` be split into smaller, more focused modules?**
  _Cohesion score 0.1111111111111111 - nodes in this community are weakly interconnected._