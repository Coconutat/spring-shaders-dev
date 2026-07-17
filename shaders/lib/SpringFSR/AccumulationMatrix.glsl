// SpringFSR Accumulation Matrix — FSR3 帧计数累积
// 跟踪累积帧数，blend = 1.0 / frames。
// 运动/遮挡时重置为 1。

#ifndef SPRINGFSR_ACCUMULATION_INCLUDED
#define SPRINGFSR_ACCUMULATION_INCLUDED

#define SPRINGFSR_MAX_ACCUMULATION 64.0

float updateAccumulation(float prevFrames, float velocityLen, float lock, float reactive) {
    float f = prevFrames + 1.0;
    if (velocityLen > 2.0 || reactive > 0.5) f = 1.0;
    return min(f, SPRINGFSR_MAX_ACCUMULATION);
}

float accumulationBlend(float frames) {
    return 1.0 / max(frames, 1.0);
}

#endif
