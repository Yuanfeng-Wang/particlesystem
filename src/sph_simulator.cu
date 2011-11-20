#ifndef __SPH_SIMULATOR_CU__
#define __SPH_SIMULATOR_CU__

#include "sph_simulator.cuh"
#include "sph_kernel.cu"

#include "buffer_abstract.h"
#include "buffer_vertex.h"
#include "buffer_memory.cuh"
#include "buffer_manager.cuh"
#include "sph_kernels.cu"
#include "utils.cuh"

#include <iostream>

using namespace std;
using namespace Settings;

namespace SPH {

    ////////////////////////////////////////////////////////////////////////////

    Simulator::Simulator () {

    }

    ////////////////////////////////////////////////////////////////////////////

    Simulator::~Simulator() {
        delete this->_bufferManager;
        delete this->_grid;
        delete this->_database;
    }

    ////////////////////////////////////////////////////////////////////////////

    void Simulator::init() {
        this->_numParticles = 8*8;

        this->_createBuffers();

        this->_grid = new Grid::Uniform();
        this->_grid->allocate(this->_numParticles, 1.0f/128.0f, 1.0f);
        this->_grid->printParams();


        // DATABASE
        this->_database = new Database();
        this->_database->addUpdateCallback(this);
        this->_database
            ->insert(ParticleNumber, "Particles", this->_numParticles)
            ->insert(GridSize, "Grid size", 256.0)
            ->insert(Timestep, "Timestep", 0.0f, 1.0f, 0.002f)
            ->insert(RestDensity, "Rest density", 0.0f, 10000.0f, 1000.0f)
            ->insert(RestPressure, "Rest pressure", 0.0f, 10000.0f, 0.0f)
            ->insert(GasStiffness, "Gas Stiffness", 0.001f, 10.0f, 1.0f)
            ->insert(Viscosity, "Viscosity", 0.0f, 100.0f, 1.0f)
            ->insert(BoundaryDampening, "Bound. damp.", 0.0f, 10000.0f, 256.0f)
            ->insert(BoundaryStiffness, "Bound. stiff.", 0.0f, 100000.0f, 20000.0f)
            ->insert(VelocityLimit, "Veloc. limit", 0.0f, 10000.0f, 600.0f)
            ->insert(SimulationScale, "Sim. scale", 0.0f, 1.0f, 0.01f)
            ->insert(KineticFriction, "Kinet. fric.", 0.0f, 10000.0f, 0.0f)
            ->insert(StaticFrictionLimit, "Stat. Fric. Lim.", 0.0f, 10000.0f, 0.0f);

            float particleMass =
                ((128.0f * 1024.0f ) / this->_numParticles) * 0.0002f;
            float particleRestDist =
                0.87f *
                pow(
                    particleMass / this->_database->selectValue(RestDensity),
                    1.0f/3.0f
                );
            float boundaryDist = 0.5 * particleRestDist;
            float smoothingLength = 2.0 * particleRestDist;
            float cellSize =
                smoothingLength * this->_database->selectValue(SimulationScale);

        this->_database
            ->insert(ParticleMass, "Particle mass", particleMass)
            ->insert(ParticleRestDistance, "Part. rest dist.", particleRestDist)
            ->insert(BoundaryDistance, "Bound. dist.", boundaryDist)
            ->insert(SmootingLength, "Smooth. len.", smoothingLength)
            ->insert(CellSize, "Cell size", cellSize);

        //this->_database->print();

        this->_updateParams();



    }

    ////////////////////////////////////////////////////////////////////////////

    void Simulator::stop() {
        this->_bufferManager->freeBuffers();
        this->_grid->free();
    }

    ////////////////////////////////////////////////////////////////////////////

     float* Simulator::getPositions() {
        return (float*) this->_bufferManager->get(Positions)->get();
    }

    ////////////////////////////////////////////////////////////////////////////

    void Simulator::bindBuffers() {
        this->_bufferManager->bindBuffers();
    }

    ////////////////////////////////////////////////////////////////////////////

    void Simulator::unbindBuffers() {
        this->_bufferManager->unbindBuffers();
    }


    ////////////////////////////////////////////////////////////////////////////

    void Simulator::_step1() {
        uint numBlocks, numThreads;

        Utils::computeGridSize(this->_numParticles, 128, numBlocks, numThreads);

        Kernel::computeDensity<<<numBlocks, numThreads>>>(
            this->_numParticles,
            this->_sortedData,
            this->_grid->getData()
        );
    }

    ////////////////////////////////////////////////////////////////////////////

    void Simulator::_step2() {
        uint numBlocks, numThreads;
        Utils::computeGridSize(this->_numParticles, 128, numBlocks, numThreads);

        Kernel::computeForce<<<numBlocks, numThreads>>>(
            this->_numParticles,
            this->_sortedData,
            this->_grid->getData()
        );
    }

    ////////////////////////////////////////////////////////////////////////////

    void Simulator::integrate(int numParticles, float deltaTime) {
        uint minBlockSize, numBlocks, numThreads;
        minBlockSize = 416;
        Utils::computeGridSize(numParticles, minBlockSize, numBlocks, numThreads);


        //this->_particleData.position = (float4*)this->getPositions();

        Kernel::integrate<Data><<<numBlocks, numThreads>>>(
            numParticles,
            deltaTime,
            this->_particleData,
            this->_sortedData,
            this->_grid->getData()
        );

    }

    ////////////////////////////////////////////////////////////////////////////

    void Simulator::update() {
        this->_grid->hash((float4*) this->getPositions());
        this->_grid->sort();
        this->_orderData();

        Buffer::Memory<uint>* buffer =
            new Buffer::Memory<uint>(new Buffer::Allocator(), Buffer::Host);

        buffer->allocate(this->_numParticles);

        GridData gridData = this->_grid->getData();

        cudaMemcpy(buffer->get(), gridData.index, this->_numParticles * sizeof(uint), cudaMemcpyDeviceToHost);

        uint* e = buffer->get();

        for(uint i=0;i< this->_numParticles; i++) {
            //cout << e[i] << endl;
        }

        Buffer::Memory<float4>* posBuffer =
            new Buffer::Memory<float4>(new Buffer::Allocator(), Buffer::Host);

        posBuffer->allocate(this->_numParticles);

        cudaMemcpy(posBuffer->get(), this->_sortedData.position, this->_numParticles * sizeof(float4), cudaMemcpyDeviceToHost);
        float4* pos = posBuffer->get();

        cutilSafeCall(cutilDeviceSynchronize());

        for (uint i=0;i<this->_numParticles; i++) {
            std::cout << pos[i].x << " " << pos[i].y << " " << pos[i].z << endl;
        }

        //this->_step1();
        //this->_step2();
        this->integrate(this->_numParticles, this->_database->selectValue(Timestep));
        //cutilSafeCall(cutilDeviceSynchronize());
    }

    ////////////////////////////////////////////////////////////////////////////

    void Simulator::valueChanged(Settings::RecordType type) {
        cout << "Value changed: " << type << endl;
    }

    ////////////////////////////////////////////////////////////////////////////

    void Simulator::_createBuffers() {
        this->_bufferManager = new Buffer::Manager<Buffers>();

        //Buffer::Allocator* allocator = new Buffer::Allocator();

        Buffer::Memory<float4>* color    = new Buffer::Memory<float4>();
        Buffer::Memory<float>*  density  = new Buffer::Memory<float>();
        Buffer::Memory<float4>* force    = new Buffer::Memory<float4>();
        Buffer::Vertex<float4>* position = new Buffer::Vertex<float4>();
        Buffer::Memory<float>*  pressure = new Buffer::Memory<float>();
        Buffer::Memory<float4>* velocity = new Buffer::Memory<float4>();

        Buffer::Memory<float4>* sColor    = new Buffer::Memory<float4>();
        Buffer::Memory<float>*  sDensity  = new Buffer::Memory<float>();
        Buffer::Memory<float4>* sForce    = new Buffer::Memory<float4>();
        Buffer::Vertex<float4>* sPosition = new Buffer::Vertex<float4>();
        Buffer::Memory<float>*  sPressure = new Buffer::Memory<float>();
        Buffer::Memory<float4>* sVelocity = new Buffer::Memory<float4>();

        this->_positionsVBO = position->getVBO();

        this->_bufferManager
            ->addBuffer(Colors,           (Buffer::Abstract<void>*) color)
            ->addBuffer(Densities,        (Buffer::Abstract<void>*) density)
            ->addBuffer(Forces,           (Buffer::Abstract<void>*) force)
            ->addBuffer(Positions,        (Buffer::Abstract<void>*) position)
            ->addBuffer(Pressures,        (Buffer::Abstract<void>*) pressure)
            ->addBuffer(Velocities,       (Buffer::Abstract<void>*) velocity)
            ->addBuffer(SortedColors,     (Buffer::Abstract<void>*) sColor)
            ->addBuffer(SortedDensities,  (Buffer::Abstract<void>*) sDensity)
            ->addBuffer(SortedForces,     (Buffer::Abstract<void>*) sForce)
            ->addBuffer(SortedPositions,  (Buffer::Abstract<void>*) sPosition)
            ->addBuffer(SortedPressures,  (Buffer::Abstract<void>*) sPressure)
            ->addBuffer(SortedVelocities, (Buffer::Abstract<void>*) sVelocity);

        this->_bufferManager->allocateBuffers(this->_numParticles);

        size_t size = 0;
        size += color->getMemorySize();
        size += position->getMemorySize();
        size += density->getMemorySize();
        size += velocity->getMemorySize();
        size += force->getMemorySize();
        size += pressure->getMemorySize();
        std::cout << "Memory usage: " << 2 * size / 1024.0 / 1024.0 << " MB\n";

        // !!! WARNING !!!
        // without binding vertex buffers can't return valid pointer to memory
        this->_bufferManager->bindBuffers();

        this->_bufferManager->memsetBuffers(0);

        this->_particleData.color    = color->get();
        this->_particleData.density  = density->get();
        this->_particleData.force    = force->get();
        this->_particleData.position = position->get();
        this->_particleData.pressure = pressure->get();
        this->_particleData.velocity = velocity->get();

        this->_sortedData.color    = sColor->get();
        this->_sortedData.density  = sDensity->get();
        this->_sortedData.force    = sForce->get();
        this->_sortedData.position = sPosition->get();
        this->_sortedData.pressure = sPressure->get();
        this->_sortedData.velocity = sVelocity->get();

        this->_bufferManager->unbindBuffers();
    }

    ////////////////////////////////////////////////////////////////////////////

    void Simulator::_orderData() {
        this->_grid->emptyCells();

        uint minBlockSize, numBlocks, numThreads;
        minBlockSize = 256;
        ::Utils::computeGridSize(
            this->_numParticles,
            minBlockSize,
            numBlocks,
            numThreads
        );

        uint sharedMemory = (numThreads + 1) * sizeof(uint);

        Kernel::update<Data><<<numBlocks, numThreads, sharedMemory>>>(
            this->_numParticles,
            this->_particleData,
            this->_sortedData,
            this->_grid->getData()
         );

    }

    ////////////////////////////////////////////////////////////////////////////

    void Simulator::_updateParams() {

        // FLUID PARAMETERS
        this->_fluidParams.restDensity =
            this->_database->selectValue(RestDensity);

        this->_fluidParams.restPressure =
            this->_database->selectValue(RestPressure);

        this->_fluidParams.gasStiffness =
            this->_database->selectValue(GasStiffness);

        this->_fluidParams.viscosity =
            this->_database->selectValue(Viscosity);

        this->_fluidParams.particleMass =
            this->_database->selectValue(ParticleMass);
        this->_fluidParams.particleRestDistance =
            this->_database->selectValue(ParticleRestDistance);

        this->_fluidParams.boundaryDistance =
            this->_database->selectValue(BoundaryDistance);
        this->_fluidParams.boundaryStiffness =
            this->_database->selectValue(BoundaryStiffness);
        this->_fluidParams.boundaryDampening =
            this->_database->selectValue(BoundaryDampening);

        this->_fluidParams.velocityLimit =
            this->_database->selectValue(VelocityLimit);

        this->_fluidParams.scaleToSimulation =
            this->_database->selectValue(SimulationScale);

        cout << "Scale:" << this->_fluidParams.scaleToSimulation << endl;

        this->_fluidParams.smoothingLength =
            this->_database->selectValue(SmootingLength);

        this->_fluidParams.frictionKinetic =
            this->_database->selectValue(KineticFriction);

        this->_fluidParams.frictionStaticLimit =
            this->_database->selectValue(StaticFrictionLimit);

        // PRECALCULATED PARAMETERS
        float smoothLen = this->_fluidParams.smoothingLength;

        this->_precalcParams.smoothLenSq = pow(smoothLen, 2);

        this->_precalcParams.poly6Coeff =
            Kernels::Poly6::getConstant(smoothLen);

        this->_precalcParams.spikyGradCoeff =
            Kernels::Spiky::getGradientConstant(smoothLen);

        this->_precalcParams.viscosityLapCoeff =
            Kernels::Spiky::getLaplacianConstant(smoothLen);

        this->_precalcParams.pressurePrecalc =
            -0.5 * this->_precalcParams.spikyGradCoeff;

        this->_precalcParams.viscosityPrecalc =
            this->_fluidParams.viscosity *
            this->_precalcParams.viscosityLapCoeff;

        // Copy parameters to GPU's constant memory
        // declarations of symbols are in sph_kernel.cu
        CUDA_SAFE_CALL(
            cudaMemcpyToSymbol(
                cudaFluidParams,
                &this->_fluidParams,
                sizeof(FluidParams)
            )
        );

        CUDA_SAFE_CALL(
            cudaMemcpyToSymbol(
                cudaPrecalcParams,
                &this->_precalcParams,
                sizeof(PrecalcParams)
            )
        );

        CUDA_SAFE_CALL(cudaThreadSynchronize());
    }

    ////////////////////////////////////////////////////////////////////////////

    ////////////////////////////////////////////////////////////////////////////

    ////////////////////////////////////////////////////////////////////////////

    ////////////////////////////////////////////////////////////////////////////


};

#endif // __SPH_SIMULATOR_CU__
