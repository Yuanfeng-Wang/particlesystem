#ifndef __BUFFER_MANAGER_CU__
#define __BUFFER_MANAGER_CU__

#include "buffer_manager.cuh"
#include "buffer_abstract_buffer.cpp"

namespace Buffer {

    ///////////////////////////////////////////////////////////////////////////

    template <class T>
    Manager<T>::Manager() {

    }

    ///////////////////////////////////////////////////////////////////////////

    template <class T>
    Manager<T>::~Manager() {
        for(this->_iterator = this->_buffers.begin();
            this->_iterator != this->_buffers.end();
            ++this->_iterator
        ) {
            AbstractBuffer<void> *buffer = this->_iterator->second;
            buffer->free();
            delete buffer;
        }
    }

    ///////////////////////////////////////////////////////////////////////////

    template <class T>
    void Manager<T>::addBuffer(T id, AbstractBuffer<void>* buffer) {
        this->_buffers[id] = buffer;
    }

    ///////////////////////////////////////////////////////////////////////////

    template <class T>
    void Manager<T>::removeBuffer(T id) {
        this->_iterator = this->_buffers->find(id);

        for(this->_iterator = this->_buffers.begin();
            this->_iterator != this->_buffers.end();
        ++this->_iterator
        ) {
            this->_buffers.erase(id);
            delete this->_iterator->second;
        }

    }

    ///////////////////////////////////////////////////////////////////////////

    template <class T>
    void Manager<T>::allocateBuffers(size_t size) {

        for(this->_iterator = this->_buffers.begin();
            this->_iterator != this->_buffers.end();
        ++this->_iterator
        ) {
            AbstractBuffer<void> *buffer = this->_iterator->second;
            buffer->allocate(size);
        }
    }

    ///////////////////////////////////////////////////////////////////////////

    template <class T>
    void Manager<T>::freeBuffers() {

        for(this->_iterator = this->_buffers.begin();
            this->_iterator != this->_buffers.end();
        ++this->_iterator
        ) {
            AbstractBuffer<void> *buffer = this->_iterator->second;
            buffer->free();
        }
    }

    ///////////////////////////////////////////////////////////////////////////

    template <class T>
    void Manager<T>::memsetBuffers(int value) {

        for(this->_iterator = this->_buffers.begin();
            this->_iterator != this->_buffers.end();
        ++this->_iterator
        ) {
            AbstractBuffer<void> *buffer = this->_iterator->second;
            buffer->memset(value);
        }
    }

    ///////////////////////////////////////////////////////////////////////////

    template <class T>
    AbstractBuffer<void>* Manager<T>::get(T id) {
        if (this->_buffers.find(id) != this->_buffers->end()) {
            return this->_buffers[id];
        } else {
            return NULL;
        }
    }

    ///////////////////////////////////////////////////////////////////////////

    template <class T>
    AbstractBuffer<void>* Manager<T>::operator[](T id) {
        return this->get(id);
    }

    ///////////////////////////////////////////////////////////////////////////

}

#endif // __BUFFER_MANAGER_CU__