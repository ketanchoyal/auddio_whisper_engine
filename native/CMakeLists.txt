cmake_minimum_required(VERSION 3.22)
project(auddio_whisper LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(WHISPER_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/whisper.cpp")
if(NOT EXISTS "${WHISPER_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "whisper.cpp not found at ${WHISPER_DIR}. Run scripts/fetch_whisper.sh first.")
endif()

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)

add_subdirectory("${WHISPER_DIR}" "${CMAKE_BINARY_DIR}/whisper" EXCLUDE_FROM_ALL)

add_library(auddio_whisper SHARED
  "${CMAKE_CURRENT_SOURCE_DIR}/src/auddio_whisper_bridge.cpp"
)

target_include_directories(auddio_whisper PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${WHISPER_DIR}/include"
  "${WHISPER_DIR}/ggml/include"
)

target_link_libraries(auddio_whisper PRIVATE whisper)

set_target_properties(auddio_whisper PROPERTIES
  C_VISIBILITY_PRESET hidden
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
)

if(APPLE)
  set_target_properties(auddio_whisper PROPERTIES
    FRAMEWORK TRUE
    MACOSX_FRAMEWORK_IDENTIFIER com.audiio.whisper
    MACOSX_FRAMEWORK_BUNDLE_VERSION 1
    MACOSX_FRAMEWORK_SHORT_VERSION_STRING 1.0
  )
endif()
