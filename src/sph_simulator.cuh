#ifndef __SPH_SIMULATOR_CUH__
#define __SPH_SIMULATOR_CUH__


#include <cutil_math.h>
#include "buffer_manager.cuh"
#include "buffer_vertex.h"
#include "colors.cuh"
#include "grid_uniform.cuh"
#include "marching_renderer.cuh"
#include "particles.h"
#include "particles_simulator.h"
#include "settings.h"
#include "settings_database.h"
#include "sph.h"

namespace SPH {

    class Simulator : public Particles::Simulator {

        public:

            /**
             * Constructor
             */
            Simulator();

            /**
             * Destructor
             */
            ~Simulator();

            /**
             * Initialize simulator
             *
             * !!! Important !!!
             * Don't call before the GL context is created
             * else can cause segmentation fault
             * Must be called as first method
             */
            void init(uint numParticles);

            /**
             * Stop simulator
             *
             * !!! Important !!!
             * Call before the GL context is deleted else
             * can cause segmentation fault
             * Must be called as last method
             */
            void stop();

            /**
             * Update simulator (integrate)
             *
             * @param animate - run animation, if false only rendering works
             * @param x - gravity x coord
             * @param y - gravity y coord
             * @param z - gravity z coord
             */
            void update(bool animate, float x, float y, float z);

            /**
             * Get positions array (GPU) pointer
             */
            float* getPositions();

            /**
             * Get colors array (GPU) pointer
             */
            float* getColors();

            /**
             * Bind simulator buffers
             * Call before using GPU pointers
             */
            void bindBuffers();

            /**
             * Unbind buffers
             * Call after using GPU pointers
             */
            void unbindBuffers();

            /**
             * Database value change callback function
             *
             * @param type - type (key) of database record
             */
            void valueChanged(Settings::RecordType type);

            /**
             * (Re)Generate particles and their positions and colors
             */
            void generateParticles();

            /**
             * Get number of vertices generated by rendering method
             */
            uint getNumVertices();

            /**
             * Set rendering method
             */
            void setRenderMode(int mode);

            /**
             * Get rendering method
             */
            int getRenderMode();

            /**
             * Get min and max positions of grid
             */
            Particles::GridMinMax getGridMinMax();

        protected:

            Buffer::Manager<Buffers> *_bufferManager;
            Buffer::Vertex<float4>* _positionsBuffer;

            Grid::Uniform* _grid;

            Data _particleData;
            Data _sortedData;

            FluidParams _fluidParams;
            PrecalcParams _precalcParams;
            GridParams _gridParams;

            Marching::Renderer* _marchingRenderer;
            int _renderMode;

            cudaEvent_t _startFPS;
            cudaEvent_t _stopFPS;
            uint _iterFPS;
            uint _sumTimeFPS;

            uint _lastAnimatedParticle;
            uint _numAnimatedParticles;

            float _animationForce;

            bool _animChangeAxis;

            Colors::Gradient _colorGradient;
            Colors::Source _colorSource;

        private:
            /**
             * Integrate simulator
             *
             * @param deltaTime - integration step
             * @param gravity - gravity vector
             */
            void _integrate (float deltaTime, float3 gravity);

            /**
             * Create simulator buffers
             * (positions, colors, densities, forces, etc.)
             */
            void _createBuffers();

            /**
             * Order hashed data by hash keys
             */
            void _orderData();

            /**
             * Update database record in GPU costant memory
             */
            void _updateParams();

            /**
             * Calculate densities and pressures
             */
            void _step1();

            /**
             * Calculate force vectors (pressure and viscosity)
             */
            void _step2();

            /**
             * Run animation
             */
            void _animate();

    };

};

#endif // __SPH_SIMULATOR_CUH__
