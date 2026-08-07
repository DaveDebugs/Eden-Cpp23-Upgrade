add_executable(eden-dump
    main.cpp
    ../tests/common/undefined_fix.cpp
)

target_link_libraries(eden-dump PRIVATE common core input_common video_core)

if (MSVC)
    target_link_libraries(eden-dump PRIVATE getopt)
endif()

target_link_libraries(eden-dump PRIVATE ${PLATFORM_LIBRARIES} Threads::Threads fmt::fmt Vulkan::Headers Vulkan::UtilityHeaders GPUOpen::VulkanMemoryAllocator iphlpapi)

if (MSVC)
    target_compile_options(eden-dump PRIVATE
        /W4
        /WX
    )
else()
    target_compile_options(eden-dump PRIVATE
        -Wall
        -Werror
    )
endif()
