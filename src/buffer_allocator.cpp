#include "buffer_allocator.h"

#include <stdlib.h>

namespace Buffer {

    ////////////////////////////////////////////////////////////////////////////

    Allocator* Allocator::_instance = NULL;

    ////////////////////////////////////////////////////////////////////////////

    Allocator* Allocator::getInstance() {
        if (Allocator::_instance == NULL) {
            Allocator::_instance = new Allocator();
        }

        return Allocator::_instance;
    }

    ////////////////////////////////////////////////////////////////////////////

    Allocator::Allocator() {
        this->_hAllocatedMemory = 0;
        this->_dAllocatedMemory = 0;
    }

    ////////////////////////////////////////////////////////////////////////////

    Allocator::~Allocator() {

    }

    ////////////////////////////////////////////////////////////////////////////

    error_t Allocator::allocate(void** ptr, size_t size, memory_t memory) {
        error_t error;

        switch (memory) {
            case Host:
                error = this->_allocateHost(ptr, size);
                break;
            case Device:
                error = this->_allocateDevice(ptr, size);
                break;
            default:
                error = UnknownMemoryTypeError;
                break;
        }

        return error;
    }

    ////////////////////////////////////////////////////////////////////////////

    error_t Allocator::free(void **ptr, memory_t memory) {
        error_t error;

        switch (memory) {
            case Host:
                error = this->_freeHost(ptr);
                break;
            case Device:
                error = this->_freeDevice(ptr);
                break;
            default:
                error = UnknownMemoryTypeError;
        }

        return error;
    }
    ////////////////////////////////////////////////////////////////////////////

    size_t Allocator::getUsage(memory_t memory) {
        switch (memory) {
            case Host:
                return this->_hAllocatedMemory;
                break;
            case Device:
                return this->_dAllocatedMemory;
                break;
            default:
                return 0;
        }
    }

    ////////////////////////////////////////////////////////////////////////////

    error_t Allocator::_allocateHost(void **ptr, size_t size) {
        error_t error;

        *ptr = malloc(size);

        if (*ptr == NULL) {
            error = MemoryAllocationError;
        } else {
            this->_hAllocatedMemory += size;
            this->_hMemoryMap[*ptr] = size;
            error = Success;
        }

        return error;
    }

    ////////////////////////////////////////////////////////////////////////////

    error_t Allocator::_allocateDevice(void **ptr, size_t size) {
        error_t error;

        cudaError_t cudaError = cudaMalloc(ptr, size);

        if (cudaError == cudaErrorMemoryAllocation) {
            error = MemoryAllocationError;
        } else {
            this->_dAllocatedMemory += size;
            this->_dMemoryMap[*ptr] = size;
            error = Success;
        }

        return error;
    }

    ////////////////////////////////////////////////////////////////////////////

    error_t Allocator::_freeHost (void **ptr) {
        error_t error;

        if (*ptr != NULL) {
            // C function from stdlib, not class method
            ::free(*ptr);
            this->_hAllocatedMemory -= this->_hMemoryMap[*ptr];
            this->_hMemoryMap[*ptr] = 0;
            *ptr = NULL;
            error = Success;
        } else {
            error = InvalidPointerError;
        }

        return error;
    }

    ////////////////////////////////////////////////////////////////////////////

    error_t Allocator::_freeDevice (void **ptr) {
        error_t error;

        cudaError_t cudaError = cudaFree(*ptr);

        error = parseCudaError(cudaError);

        if (error == Success) {
            this->_dAllocatedMemory -= this->_dMemoryMap[*ptr];
            this->_dMemoryMap[*ptr] = 0;
            *ptr = NULL;
        }

        return error;
    }

    ////////////////////////////////////////////////////////////////////////////

}