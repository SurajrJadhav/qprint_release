cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

set(RUNNER_SOURCES
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

add_executable(${BINARY_NAME} WIN32 ${RUNNER_SOURCES})

apply_standard_settings(${BINARY_NAME})

target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

add_dependencies(${BINARY_NAME} flutter_assemble)

# SumatraPDF and LibreOffice: copy into output at build time only if present.
# Run scripts/setup_sumatra.ps1 and scripts/setup_libreoffice.ps1 to add them.
# Using a script so the build does not fail when bin/ is missing (e.g. after flutter clean).
set(SUMATRA_EXE "${CMAKE_CURRENT_SOURCE_DIR}/bin/SumatraPDF.exe")
set(LIBREOFFICE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bin/LibreOffice")
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND}
    -DSUMATRA_EXE="${SUMATRA_EXE}"
    -DLIBREOFFICE_DIR="${LIBREOFFICE_DIR}"
    -DOUT_DIR="$<TARGET_FILE_DIR:${BINARY_NAME}>"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/copy_optional_bin.cmake"
  COMMENT "Copying SumatraPDF and LibreOffice to output (if present)")
if(EXISTS "${SUMATRA_EXE}")
  message(STATUS "SumatraPDF: will copy from bin/SumatraPDF.exe")
else()
  message(STATUS "SumatraPDF: not found. Run scripts/setup_sumatra.ps1 for PDF print.")
endif()
if(EXISTS "${LIBREOFFICE_DIR}/App/libreoffice/program/soffice.exe")
  message(STATUS "LibreOffice: will copy from bin/LibreOffice/")
else()
  message(STATUS "LibreOffice: not found. Run scripts/setup_libreoffice.ps1 for Word/PPT conversion.")
endif()
