include(CMakeParseArguments)

# MASK_UNITY_BUILD: define if this library should be build normally
# UNITY_BUILD_EXCLUDE: Define if UNITY_EXCLUDED_SOURCES is defined.
# KIT: Name of the library (e.g., Common).
# LINKLIBS: List of libraries (targets) to link against.
# INCLUDES: List of header files for the library (obtain via file(GLOB ...)).
# SOURCES: List of cpp files for the library (obtain via file(GLOB ...)).
# TESTDIRS: List of subdirectories that contain tests (and a CMakeLists.txt).
# UNITY_BUILD_EXCLUDED_SOURCES: List of sources to exclude from unity build in 
#   case of conflicts.
#
# Here's an example:
#
#   addLibrary(
#       UNITY_EXCLUDE
#       KIT Common
#       LINKLIBS ${Simbody_LIBRARIES}
#       INCLUDES ${INCLUDES}
#       SOURCES ${SOURCES}
#       TESTDIRS "test"
#       UNITY_EXCLUDED_SOURCES ${EXCLUDED_SOURCES}
#   )
function(addLibrary)

    # Parse arguments.
    # ----------------
    # http://www.cmake.org/cmake/help/v2.8.9/cmake.html#module:CMakeParseArguments
    set(options MASK_UNITY_BUILD UNITY_BUILD_EXCLUDE)
    set(oneValueArgs KIT)
    set(multiValueArgs LINKLIBS INCLUDES SOURCES TESTDIRS UNITY_BUILD_EXCLUDED_SOURCES)
    cmake_parse_arguments(
        ADDLIB "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # Version stuff.
    # --------------
    set(ADDLIB_LIBRARY_NAME ${ADDLIB_KIT})
    set(PROJECT_LIBRARIES ${PROJECT_LIBRARIES} ${ADDLIB_KIT} CACHE INTERNAL "")
    
    # Unity Build
    if((NOT ADDLIB_MASK_UNITY_BUILD) AND USE_UNITY_BUILD)
        if(ADDLIB_UNITY_EXCLUDE)
            unityBuild(
                EXCLUDE_FROM_SOURCES
                UNIT_SUFFIX ${ADDLIB_LIBRARY_NAME}
                PROJECT_SOURCES ADDLIB_SOURCES
                EXCLUDED_SOURCES ${ADDLIB_UNITY_BUILD_EXCLUDED_SOURCES}
            )
        else()
            unityBuild(
                UNIT_SUFFIX ${ADDLIB_LIBRARY_NAME}
                PROJECT_SOURCES ADDLIB_SOURCES
            )
        endif()
    endif()

    # Create the library using the provided source and include files.
    add_library(${ADDLIB_LIBRARY_NAME} SHARED
        ${ADDLIB_SOURCES} ${ADDLIB_INCLUDES})

    # This target links to the libraries provided as arguments to this func.
    target_link_libraries(${ADDLIB_LIBRARY_NAME} ${ADDLIB_LINKLIBS})

    set_target_properties(${ADDLIB_LIBRARY_NAME}         
        PROPERTIES    
        PROJECT_LABEL ${ADDLIB_LIBRARY_NAME}
        FOLDER "Libraries"       
    )
    
    # Install.
    # --------
    # Shared libraries are needed at runtime for applications, so we put them
    # at the top level in bin/*.dll (Windows) or lib/*.so
    # (Linux) or lib/*.dylib (Mac). Windows .lib files, and Linux/Mac
    # .a static archives are only needed at link time so go in sdk/lib.
    install(TARGETS ${ADDLIB_LIBRARY_NAME}
        RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
        LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}"
        ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}")

    # Install headers.
    # ----------------
    set(_INCLUDE_PREFIX "${CMAKE_INSTALL_INCLUDEDIR}")
    set(_INCLUDE_PREFIX ${_INCLUDE_PREFIX}/${CMAKE_PROJECT_NAME})
    set(_INCLUDE_LIBNAME ${ADDLIB_KIT})
    install(FILES ${ADDLIB_INCLUDES}
            DESTINATION ${_INCLUDE_PREFIX}/${_INCLUDE_LIBNAME})

    # Testing.
    # --------
    enable_testing()

    if(BUILD_TESTING)
        foreach(ADDLIB_TESTDIR ${ADDLIB_TESTDIRS})
            subdirs("${ADDLIB_TESTDIR}")
        endforeach()
    endif()

endfunction()


# Create test targets for this directory.
# TESTPROGRAMS: Names of test CPP files. One test will be created for each cpp
#   of these files.
# DATAFILES: Files necessary to run the test. These will be copied into the
#   corresponding build directory.
# LINKLIBS: Arguments to TARGET_LINK_LIBRARIES.
# SOURCES: Extra source files for the executable.
#
# Here's an example:
#   file(GLOB TEST_PROGRAMS "test*.cpp")
#   file(GLOB DATA_FILES *.osim *.xml *.sto *.mot)
#   addTests(
#       TESTGROUP Name
#       TESTPROGRAMS ${TEST_ROGRAMS}
#       DATAFILES ${DATA_FILES}
#       LINKLIBS osimCommon osimSimulation osimAnalyses
#       )
function(addTests)

    if(BUILD_TESTING)

        # Parse arguments.
        # ----------------
        # http://www.cmake.org/cmake/help/v2.8.9/cmake.html#module:CMakeParseArguments
        set(options)
        set(oneValueArgs TESTGROUP)
        set(multiValueArgs TESTPROGRAMS DATAFILES LINKLIBS SOURCES)
        cmake_parse_arguments(
            ADDTESTS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

        # If EXECUTABLE_OUTPUT_PATH is set, then that's where the tests will be
        # located. Otherwise, they are located in the current binary directory.
        if(EXECUTABLE_OUTPUT_PATH)
            set(TEST_PATH "${EXECUTABLE_OUTPUT_PATH}")
        else()
            set(TEST_PATH "${CMAKE_CURRENT_BINARY_DIR}")
        endif()

        # Make test targets.
        foreach(test_program ${ADDTESTS_TESTPROGRAMS})
            # NAME_WE stands for "name without extension"
            get_filename_component(TEST_NAME ${test_program} NAME_WE)

            add_executable(${TEST_NAME} ${test_program}
                ${ADDTESTS_SOURCES})
            target_link_libraries(${TEST_NAME} ${ADDTESTS_LINKLIBS})
            add_test(NAME ${TEST_NAME} COMMAND ${TEST_NAME})
            set_target_properties(${TEST_NAME} PROPERTIES
                PROJECT_LABEL "${ADDTESTS_TESTGROUP} - ${TEST_NAME}"
                FOLDER "Tests"
            )

        endforeach()

        # Copy data files to build directory.
        foreach(data_file ${ADDTESTS_DATAFILES})
            # This command re-copies the data files if they are modified;
            # custom commands don't do this.
            file(COPY "${data_file}" DESTINATION "${CMAKE_CURRENT_BINARY_DIR}")
        endforeach()

        #if(UNIX)
        #  add_definitions(-fprofile-arcs -ftest-coverage)
        #  link_libraries(gcov)
        #endif(UNIX)

    endif()

endfunction()


# Create unity build
# EXCLUDE_FROM_SOURCES: Defined if EXCLUDED_SOURCES are provided.
# PROJECT_SOURCES: The sources that will be compiled into a single unit.
#   Should be provided by reference (e.g. SOURCES, not ${SOURCES}).
# EXCLUDED_SOURCES: List of sources to exclude from unity build in 
#   case of conflicts.
#
# Example:
#       OsimUnityBuild(
#           EXCLUDE_FROM_SOURCES
#           PROJECT_SOURCES sources
#           EXCLUDED_SOURCES ${excluded}
#       )
function(unityBuild)

    # Parse arguments.
    # ----------------
    # http://www.cmake.org/cmake/help/v2.8.9/cmake.html#module:CMakeParseArguments
    set(options EXCLUDE_FROM_SOURCES)
    set(oneValueArgs UNIT_SUFFIX)
    set(multiValueArgs PROJECT_SOURCES EXCLUDED_SOURCES)
    cmake_parse_arguments(
        UNITYBUILD "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    
    set(files ${${UNITYBUILD_PROJECT_SOURCES}})
    
    if (UNITYBUILD_EXCLUDE_FROM_SOURCES)
        list(REMOVE_ITEM files ${UNITYBUILD_EXCLUDED_SOURCES})
    endif()
    
    # Generate a unique filename for the unity build translation unit
    set(unit_build_file ${CMAKE_CURRENT_BINARY_DIR}/${UNITYBUILD_UNIT_SUFFIX}_UnityBuild.cpp)
    
    # Exclude all translation units from compilation
    set_source_files_properties(${files} PROPERTIES HEADER_FILE_ONLY true)
    
    # Open the unity build file
    file(WRITE ${unit_build_file} "// Unity Build generated by CMake\n")
    
    # Add include statement for each translation unit
    foreach(source_file ${files} )
        file( APPEND ${unit_build_file} "#include <${source_file}>\n")
    endforeach(source_file)
    
    # Complement list of translation units with the name of ub
    set(${UNITYBUILD_PROJECT_SOURCES} ${${UNITYBUILD_PROJECT_SOURCES}} ${unit_build_file} PARENT_SCOPE)  
    
endfunction()

# Create test targets for this directory.
# TESTPROGRAMS: Names of test CPP files. One test will be created for each cpp
#   of these files.
# DATAFILES: Files necessary to run the test. These will be copied into the
#   corresponding build directory.
# LINKLIBS: Arguments to TARGET_LINK_LIBRARIES.
# SOURCES: Extra source files for the exectuable.
#
# Here's an example:
#   file(GLOB TEST_PROGRAMS "test*.cpp")
#   file(GLOB DATA_FILES *.osim *.xml *.sto *.mot)
#   addTests(
#       TESTPROGRAMS ${TEST_ROGRAMS}
#       DATAFILES ${DATA_FILES}
#       LINKLIBS osimCommon osimSimulation osimAnalyses
#   )
function(addTests)

    if(BUILD_TESTING)

        # Parse arguments.
        # ----------------
        # http://www.cmake.org/cmake/help/v2.8.9/cmake.html#module:CMakeParseArguments
        set(options)
        set(oneValueArgs)
        set(multiValueArgs TESTPROGRAMS DATAFILES LINKLIBS SOURCES)
        cmake_parse_arguments(
            ADDTESTS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

        # If EXECUTABLE_OUTPUT_PATH is set, then that's where the tests will be
        # located. Otherwise, they are located in the current binary directory.
        if(EXECUTABLE_OUTPUT_PATH)
            set(TEST_PATH "${EXECUTABLE_OUTPUT_PATH}")
        else()
            set(TEST_PATH "${CMAKE_CURRENT_BINARY_DIR}")
        endif()

        # Make test targets.
        foreach(test_program ${ADDTESTS_TESTPROGRAMS})
            # NAME_WE stands for "name without extension"
            get_filename_component(TEST_NAME ${test_program} NAME_WE)

            add_executable(${TEST_NAME} ${test_program}
                ${ADDTESTS_SOURCES})
            target_link_libraries(${TEST_NAME} ${ADDTESTS_LINKLIBS})
            add_test(NAME ${TEST_NAME} COMMAND ${TEST_NAME})
            set_target_properties(${TEST_NAME} PROPERTIES
                PROJECT_LABEL "Test - ${TEST_NAME}"
                FOLDER "Tests"
            )
    
        endforeach()

        # Copy data files to build directory.
        foreach(data_file ${ADDTESTS_DATAFILES})
            # This command re-copies the data files if they are modified;
            # custom commands don't do this.
            file(COPY "${data_file}" DESTINATION "${CMAKE_CURRENT_BINARY_DIR}")
        endforeach()

        #if(UNIX)
        #  add_definitions(-fprofile-arcs -ftest-coverage)
        #  link_libraries(gcov)
        #endif(UNIX)

    endif()

endfunction()

# Create an application/executable. To be used in the Appliations directory.
# APPNAME: Name of the application. Must also be the name of the source file
# containing main().
#
# Here's an example:
#   addApplication(forward)
function(addApplication)

    # Parse arguments.
    # ----------------
    # http://www.cmake.org/cmake/help/v2.8.9/cmake.html#module:CMakeParseArguments
    set(options)
    set(oneValueArgs APPNAME)
    set(multiValueArgs SOURCES LINKLIBS)
    cmake_parse_arguments(
        ADDAPPLICATION "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    add_executable(${ADDAPPLICATION_APPNAME} ${ADDAPPLICATION_SOURCES})
    target_link_libraries(${ADDAPPLICATION_APPNAME} ${ADDAPPLICATION_LINKLIBS})
    install(
        TARGETS ${ADDAPPLICATION_APPNAME} 
        DESTINATION "${CMAKE_INSTALL_BINDIR}"
    )
    set_target_properties(${ADDAPPLICATION_APPNAME} PROPERTIES
        FOLDER "Applications"
        PROJECT_LABEL "${ADDAPPLICATION_APPNAME}"
    )
endfunction()