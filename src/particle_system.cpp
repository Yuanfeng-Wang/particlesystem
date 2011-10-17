#include "particle_system.h"
#include "particle_system.cuh"
#include "cutil_math.h"

ParticleSystem::ParticleSystem(uint count, uint3 gridSize) {
    this->_count = count;
    this->_gridSize = gridSize;

    this->_initialize();
}

ParticleSystem::~ParticleSystem(){
    delete [] this->_hPositions;
    delete [] this->_hVelocities;

    this->_freeCudaArray(this->_cudaPositionsVBO);
    this->_freeCudaArray(this->_cudaColorsVBO);
    this->_freeCudaArray(this->_cudaVelocities);
    this->_freeCudaArray(this->_cudaGridHash);
    this->_freeCudaArray(this->_cudaGridIndex);
    this->_freeCudaArray(this->_cudaCellStart);
    this->_freeCudaArray(this->_cudaCellEnd);

    this->_unmapGLBufferObject(this->_cudaPositionsVBOResource);
    this->_deleteVBO(&this->_positionsVBO);
}

unsigned int  ParticleSystem::getCount() const {
    return this->_count;
}

float ParticleSystem::getRadius() const {
    return this->_paramters.particleRadius;
}

float ParticleSystem::getGravity() const {
    return this->_paramters.gravity.y;
}

void ParticleSystem::setRadius(float radius) {
    this->_paramters.particleRadius = radius;
}

void ParticleSystem::setGravity(float gravity) {
    this->_paramters.gravity = make_float3(0.0f, gravity, 0.0f);
}

void ParticleSystem::update(float deltaTime) {
    float *dPos;

    dPos = (float *) this->_mapGLBufferObject(&this->_cudaPositionsVBOResource);

    integrateSystem(
        dPos,
        this->_cudaVelocities,
        deltaTime,
        this->_count
    );

    calculateHash(
        this->_cudaGridHash,
        this->_cudaGridIndex,
        dPos,
        this->_count
    );

    // sort particles based on hash
    sortParticles(this->_cudaGridHash, this->_cudaGridIndex, this->_count);

    this->_unmapGLBufferObject(this->_cudaPositionsVBOResource);
    cutilSafeCall(cutilDeviceSynchronize());
}

void * ParticleSystem::getCudaPositionsVBO() const {
    return (void *) this->_cudaPositionsVBO;
}

void * ParticleSystem::getCudaColorsVBO() const {
    return (void *) this->_cudaColorsVBO;
}

void ParticleSystem::setPositionsVBO(GLuint vbo) {
    this->_positionsVBO = vbo;
}

void ParticleSystem::setCudaPositionsVBOResource(struct cudaGraphicsResource * resource) {
    this->_cudaPositionsVBOResource = resource;
}

GLuint ParticleSystem::getPositionsVBO() const {
    return this->_positionsVBO;
}

struct cudaGraphicsResource* ParticleSystem::getCudaPositionsVBOResource() const {
    return this->_cudaPositionsVBOResource;
}

void ParticleSystem::_initialize() {
    unsigned int memSizeF = sizeof(float) * 4 * this->_count;
    unsigned int memSizeI = sizeof(uint) * 4 * this->_count;

    // allocate host storage
    this->_hPositions = new float[this->_count*4];
    this->_hVelocities = new float[this->_count*4];

    memset(this->_hPositions, 0, memSizeF);
    memset(this->_hVelocities, 0, memSizeF);

    // create and map VBO to VBOResource
    this->_createVBO(&this->_positionsVBO);
    this->_cudaMapVBO(
        this->_positionsVBO,
        &this->_cudaPositionsVBOResource,
        cudaGraphicsMapFlagsNone
    );

    this->_allocateCudaArray((void **)&this->_cudaColorsVBO, memSizeF);
    this->_allocateCudaArray((void**)&this->_cudaVelocities, memSizeF);

    this->_allocateCudaArray((void**)&this->_cudaGridHash, memSizeI);
    this->_allocateCudaArray((void**)&this->_cudaGridIndex, memSizeI);
    this->_allocateCudaArray((void**)&this->_cudaCellStart, memSizeI);
    this->_allocateCudaArray((void**)&this->_cudaCellEnd, memSizeI);

    this->_paramters.particleRadius = 1.0f/64.0f;
    this->_paramters.boundaryDamping = -0.5f;
    this->_paramters.globalDamping = -1.0f;
    this->_paramters.gravity = make_float3(0.0f, -0.05f, 0.0f);
    this->_paramters.gridOrigin = make_float3(-1.0f, -1.0f, -1.0f);
    float cellSize = this->_paramters.particleRadius * 2;
    this->_paramters.cellSize = make_float3(cellSize, cellSize, cellSize);
    uint3 gridSize;
    gridSize.x = gridSize.y = gridSize.z = 8;
    this->_paramters.gridSize = gridSize;

    setParameters(&this->_paramters);
}

void ParticleSystem::_allocateCudaArray(void **pointer, size_t size) {
    cutilSafeCall(cudaMalloc(pointer, size));
    cutilSafeCall(cudaMemset(*pointer, 0, size));
}

void ParticleSystem::_freeCudaArray(void *pointer) {
    cutilSafeCall(cudaFree(pointer));
}

void ParticleSystem::_createVBO(GLuint *vbo) {
    // create buffer object
    glGenBuffers(1, vbo);
    glBindBuffer(GL_ARRAY_BUFFER, *vbo);

    // initialize buffer object
    unsigned int size = this->_count * 4 * sizeof(float);
    glBufferData(GL_ARRAY_BUFFER, size, 0, GL_DYNAMIC_DRAW);

    glBindBuffer(GL_ARRAY_BUFFER, 0);
}


void ParticleSystem::_deleteVBO(GLuint *vbo) {
    glBindBuffer(1, *vbo);
    glDeleteBuffers(1, vbo);
    *vbo = 0;
}

void ParticleSystem::_cudaMapVBO(GLuint vbo, struct cudaGraphicsResource **resource, unsigned int flags) {
    cutilSafeCall(cudaGraphicsGLRegisterBuffer(resource, vbo, flags));
}

void ParticleSystem::_cudaUnmapVBO(struct cudaGraphicsResource *resource) {
    cudaGraphicsUnregisterResource(resource);
}

void * ParticleSystem::_mapGLBufferObject(struct cudaGraphicsResource **resource) {
    void *pointer;
    cutilSafeCall(cudaGraphicsMapResources(1, resource, 0));
    size_t bytes;
    cutilSafeCall(
        cudaGraphicsResourceGetMappedPointer(
            (void **)&pointer,
            &bytes,
            *resource
        )
    );
    return pointer;
}

void ParticleSystem::_unmapGLBufferObject(struct cudaGraphicsResource *resource) {
    cutilSafeCall(cudaGraphicsUnmapResources(1, &resource, 0));
}