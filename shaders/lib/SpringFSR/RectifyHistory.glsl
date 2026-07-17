// SpringFSR RectifyHistory — FSR3 历史矫正
// clip 后按 lock/reactive 混合裁剪历史与原始历史。
// lock 高 → 信任裁剪历史（稳定像素）
// reactive 高 → 信任原始历史（透明/边缘）

#ifndef SPRINGFSR_RECTIFYHISTORY_INCLUDED
#define SPRINGFSR_RECTIFYHISTORY_INCLUDED

vec3 rectifyHistory(vec3 clipResult, vec3 preClipHistory, float lock, float reactive) {
    float t = lock * (1.0 - reactive);
    return mix(clipResult, preClipHistory, t);
}

#endif
