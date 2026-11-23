cmake_minimum_required(VERSION 3.22)

project(agent-shell VERSION 0.26.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Qt6 6.5 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    QuickControls2
    Network
    Svg
)

qt_standard_project_setup(REQUIRES 6.5)

set(AGENT_SHELL_INSTALL_DATADIR "${CMAKE_INSTALL_PREFIX}/share/agent-shell"
    CACHE PATH "Directory where shared QML/backend assets are installed")

qt_add_executable(agent-shell
    src/main.cpp
    src/SingleInstance.h
    src/SingleInstance.cpp
)

qt_add_qml_module(agent-shell
    URI AgentShell.Native
    VERSION 1.0
    OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/AgentShell/Native"
    SOURCES
        src/AppRuntime.h
        src/AppRuntime.cpp
        src/NativeScope.h
        src/NativeScope.cpp
        src/NativeWindow.h
        src/NativeWindow.cpp
        src/NativeProcess.h
        src/NativeProcess.cpp
        src/NativeFileView.h
        src/NativeFileView.cpp
)

target_include_directories(agent-shell PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

target_compile_definitions(agent-shell PRIVATE
    AGENT_SHELL_VERSION="${PROJECT_VERSION}"
    AGENT_SHELL_INSTALL_DATADIR="${AGENT_SHELL_INSTALL_DATADIR}"
)

target_compile_options(agent-shell PRIVATE
    -Wall
    -Wextra
    -Wpedantic
)

target_link_libraries(agent-shell PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Network
    Qt6::Svg
)

include(GNUInstallDirs)
install(TARGETS agent-shell
    RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
)
