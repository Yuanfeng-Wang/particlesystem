#ifndef __SPH_SIMULATOR_CUH__
#define __SPH_SIMULATOR_CUH__

#include <cutil_math.h>
#include "buffer_manager.cuh"
#include "buffer_vertex.h"
#include "grid_uniform.cuh"
#include "particles_simulator.h"
#include "settings.h"
#include "settings_database.h"
#include "sph.h"

namespace SPH {

    class Simulator : public Particles::Simulator {

        public:
            Simulator();
            ~Simulator();

            /**
             * Initialize simulator
             *
             * !!! Important !!!
             * Don't call before the GL context is created
             * else can cause segmentation fault
             * Must be called as first method
             */
            void init();
            void stop();
            /**
             *
             */
            void update();
            float* getPositions();
            void bindBuffers();
            void unbindBuffers();
            void integrate (int numParticles, float deltaTime, float4* pos);
            //virtual Buffer::Vertex<float>* getPositionsBuffer();

            void valueChanged(Settings::RecordType type);

        protected:


            Buffer::Manager<Buffers> *_bufferManager;
            Buffer::Vertex<float4>* _positionsBuffer;

            Grid::Uniform* _grid;
            Settings::Database* _database;

            Data _particleData;
            Data _sortedData;

        private:
            void _createBuffers();
            void _orderData();
    };

};

#endif // __SPH_SIMULATOR_CUH__
