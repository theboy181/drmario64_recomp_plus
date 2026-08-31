# The pinned RT64 Metal backend explicitly releases several autoreleased or
# borrowed objects without first retaining them. That leaves dangling objects
# for their original owners or the thread's autorelease pool to release during
# shutdown.
#
# Generate a corrected source file in the build tree instead of modifying the
# submodule. Exact-match validation makes this fail clearly when an RT64 update
# changes the affected code and the workaround needs to be reviewed.
function(apply_rt64_metal_ownership_fix target)
    set(rt64_metal_source
        "${CMAKE_SOURCE_DIR}/lib/rt64/src/metal/rt64_metal.cpp"
    )
    set(rt64_metal_patched_source
        "${CMAKE_BINARY_DIR}/rt64/src/metal/rt64_metal_macos.cpp"
    )

    file(READ "${rt64_metal_source}" rt64_metal_contents)

    set(texture_descriptor_creation
        "        MTL::TextureDescriptor *descriptor = MTL::TextureDescriptor::textureBufferDescriptor(pixelFormat, width, options, usage);\n"
    )
    set(texture_descriptor_retained
        "${texture_descriptor_creation}        descriptor->retain();\n"
    )
    string(FIND "${rt64_metal_contents}" "${texture_descriptor_creation}" texture_descriptor_position)
    if (texture_descriptor_position EQUAL -1)
        message(FATAL_ERROR
            "Unable to apply the RT64 Metal texture descriptor ownership fix. "
            "Review the pinned RT64 source and update this workaround."
        )
    endif()
    string(REPLACE
        "${texture_descriptor_creation}"
        "${texture_descriptor_retained}"
        rt64_metal_contents
        "${rt64_metal_contents}"
    )

    set(shader_function_name_creation
        "        this->functionName = (entryPointName != nullptr) ? NS::String::string(entryPointName, NS::UTF8StringEncoding) : MTLSTR(\"\");\n"
    )
    set(shader_function_name_retained
        "${shader_function_name_creation}        this->functionName->retain();\n"
    )
    string(FIND "${rt64_metal_contents}" "${shader_function_name_creation}" shader_function_name_position)
    if (shader_function_name_position EQUAL -1)
        message(FATAL_ERROR
            "Unable to apply the RT64 Metal shader name ownership fix. "
            "Review the pinned RT64 source and update this workaround."
        )
    endif()
    string(REPLACE
        "${shader_function_name_creation}"
        "${shader_function_name_retained}"
        rt64_metal_contents
        "${rt64_metal_contents}"
    )

    set(swap_chain_layer_creation
        "        this->layer = static_cast<CA::MetalLayer*>(renderWindow.view);\n"
    )
    set(swap_chain_layer_retained
        "${swap_chain_layer_creation}        layer->retain();\n"
    )
    string(FIND "${rt64_metal_contents}" "${swap_chain_layer_creation}" swap_chain_layer_position)
    if (swap_chain_layer_position EQUAL -1)
        message(FATAL_ERROR
            "Unable to apply the RT64 Metal swap chain layer ownership fix. "
            "Review the pinned RT64 source and update this workaround."
        )
    endif()
    string(REPLACE
        "${swap_chain_layer_creation}"
        "${swap_chain_layer_retained}"
        rt64_metal_contents
        "${rt64_metal_contents}"
    )

    set(device_creation
        "        this->mtl = renderInterface->device;\n"
    )
    set(device_retained
        "${device_creation}        this->mtl->retain();\n"
    )
    string(FIND "${rt64_metal_contents}" "${device_creation}" device_position)
    if (device_position EQUAL -1)
        message(FATAL_ERROR
            "Unable to apply the RT64 Metal device ownership fix. "
            "Review the pinned RT64 source and update this workaround."
        )
    endif()
    string(REPLACE
        "${device_creation}"
        "${device_retained}"
        rt64_metal_contents
        "${rt64_metal_contents}"
    )

    set(command_buffer_creation
        "        mtl = queue->mtl->commandBufferWithUnretainedReferences();\n"
    )
    set(command_buffer_retained
        "${command_buffer_creation}        mtl->retain();\n"
    )
    string(FIND "${rt64_metal_contents}" "${command_buffer_creation}" command_buffer_position)
    if (command_buffer_position EQUAL -1)
        message(FATAL_ERROR
            "Unable to apply the RT64 Metal command buffer ownership fix. "
            "Review the pinned RT64 source and update this workaround."
        )
    endif()
    string(REPLACE
        "${command_buffer_creation}"
        "${command_buffer_retained}"
        rt64_metal_contents
        "${rt64_metal_contents}"
    )

    set(blit_encoder_creation
        "            activeBlitEncoder = mtl->blitCommandEncoder(device->renderInterface->reusableBlitDescriptor);\n"
    )
    set(blit_encoder_retained
        "${blit_encoder_creation}            activeBlitEncoder->retain();\n"
    )
    string(FIND "${rt64_metal_contents}" "${blit_encoder_creation}" blit_encoder_position)
    if (blit_encoder_position EQUAL -1)
        message(FATAL_ERROR
            "Unable to apply the RT64 Metal blit encoder ownership fix. "
            "Review the pinned RT64 source and update this workaround."
        )
    endif()
    string(REPLACE
        "${blit_encoder_creation}"
        "${blit_encoder_retained}"
        rt64_metal_contents
        "${rt64_metal_contents}"
    )

    set(resolve_encoder_creation
        "            activeResolveComputeEncoder = mtl->computeCommandEncoder();\n"
    )
    set(resolve_encoder_retained
        "${resolve_encoder_creation}            activeResolveComputeEncoder->retain();\n"
    )
    string(FIND "${rt64_metal_contents}" "${resolve_encoder_creation}" resolve_encoder_position)
    if (resolve_encoder_position EQUAL -1)
        message(FATAL_ERROR
            "Unable to apply the RT64 Metal resolve encoder ownership fix. "
            "Review the pinned RT64 source and update this workaround."
        )
    endif()
    string(REPLACE
        "${resolve_encoder_creation}"
        "${resolve_encoder_retained}"
        rt64_metal_contents
        "${rt64_metal_contents}"
    )

    file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/rt64/src/metal")
    file(WRITE "${rt64_metal_patched_source}" "${rt64_metal_contents}")

    get_target_property(rt64_sources "${target}" SOURCES)
    list(FIND rt64_sources "${rt64_metal_source}" rt64_metal_source_position)
    if (rt64_metal_source_position EQUAL -1)
        message(FATAL_ERROR
            "Unable to replace RT64's Metal source with the ownership-fixed copy."
        )
    endif()

    list(REMOVE_ITEM rt64_sources "${rt64_metal_source}")
    list(APPEND rt64_sources "${rt64_metal_patched_source}")
    set_property(TARGET "${target}" PROPERTY SOURCES "${rt64_sources}")
    target_include_directories("${target}" PRIVATE
        "${CMAKE_SOURCE_DIR}/lib/rt64/src/metal"
    )
endfunction()
