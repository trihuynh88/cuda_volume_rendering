# cuda_volume_rendering

Steps to compile the code on Midway server:
1) Request a GPU compute node (change the --time option for how long the session lasts):
sinteractive --time=00:30:00 --partition=gpu --nodes=1  --gres=gpu:1
2) Load CUDA and Teem libs:
module load cuda/7.5
module load teem
3) Compile the code:
nvcc volume_renderer.cu Image.cpp -o volume_renderer -lteem

Example calling for the sample dataset:
./volume_renderer -i 270.nrrd -fr 2453.95 1850.87 4520.28 -at 2575.22 2259.17 461.956 -up -0.996969 0.0745429 -0.0222908 -nc -400 -fc 400 -fov 18 -isize 726 528 -ldir -1 -1 -2 -step 0.2 -iso 1800 -thick 0.5
