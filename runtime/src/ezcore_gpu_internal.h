/* Private layout shared by the GPU backends and the dispatcher.
 *
 * Why this exists: ezcore_gpu.c must decide whether a context belongs to the
 * windowing backend or to Vulkan, but each backend owns an opaque struct whose
 * fields it alone understands. The first version of the dispatcher called
 * ezcore_gpu_platform_api(ctx) to make that decision, which would have read a
 * Vulkan context through the GL backend's layout -- undefined behaviour, and
 * the kind that passes on a machine with one GPU and corrupts on another.
 *
 * The fix is a tagged prefix: every context begins with this header, so the
 * dispatcher can route on backend without knowing anything else, and each
 * backend's own fields follow after it. The tag is an enum rather than a bool
 * so a third backend (D3D, Metal) is an addition, not a reinterpretation.
 *
 * This header is private to runtime/src. It is not installed and not part of
 * the public ABI.
 */
#ifndef EZCORE_GPU_INTERNAL_H
#define EZCORE_GPU_INTERNAL_H

#include "ezcore_gpu.h"

enum ezcore_gpu_backend_id {
  EZCORE_BACKEND_NONE = 0,
  EZCORE_BACKEND_WINDOW = 1, /* EGL / WGL / CGL */
  EZCORE_BACKEND_VULKAN = 2
};

struct ezcore_gpu_context {
  enum ezcore_gpu_backend_id backend;
  enum ezcore_gpu_api api;
  unsigned version_major;
  unsigned version_minor;
  bool headless;
  /* Generation counter, bumped on every context_reset. A core holding GL
   * resources across a reset must recreate them; the counter is what lets
   * the host tell that happened, and what a test can assert on instead of
   * inferring it from a framebuffer name. */
  unsigned generation;
};

struct ezcore_gpu_vk_body {
  struct ezcore_gpu_context head;
  void *loader;          /* dlopen handle for libvulkan, or NULL */
  void *instance;        /* VkInstance  */
  void *physical_device; /* VkPhysicalDevice */
  void *device;          /* VkDevice   */
  void *queue;           /* VkQueue    */
  unsigned queue_index;
  unsigned queue_family;
  unsigned image_index;  /* what current_framebuffer reports */
  /* Resolved entry points. The Vk* handles themselves are opaque pointers --
   * this runtime never dereferences them, so it needs no Vulkan SDK headers
   * and no -lvulkan, which is what lets it load on a machine with no Vulkan
   * driver at all (ADR-018 Q6). Signatures are hand-declared to match the
   * Vulkan ABI; only pointers are passed, so no struct layout is relied on. */
  /* Resolved entry points, declared with their real Vulkan signatures. They
   * are hand-written rather than pulled from <vulkan/vulkan.h> so the runtime
   * needs no Vulkan SDK headers and no -lvulkan, which is what lets it load on
   * a machine with no Vulkan driver at all (ADR-018 Q6). Only pointers cross
   * these boundaries, so no Vulkan struct layout is relied on anywhere --
   * except the three create-info structs in ezcore_gpu_vulkan.c, whose layouts
   * ARE depended on, and which are therefore spelled out there next to their
   * use with a comment saying so.
   */
  struct ezcore_vk_table {
    int (*CreateInstance)(const void *, const void *, void **);
    void (*DestroyInstance)(void *, const void *);
    int (*EnumeratePhysicalDevices)(void *, unsigned *, void **);
    int (*GetPhysicalDeviceQueueFamilyProperties)(void *, unsigned *, void *);
    int (*CreateDevice)(void *, const void *, const void *, void **);
    void (*DestroyDevice)(void *, const void *);
    /* VkQueue* -- a single opaque handle, NOT a pointer-to-pointer.
     * The first version declared this as `void **` (the shape used for
     * CreateDevice, which really does take VkDevice**), so the callee
     * wrote a handle where a pointer-to-a-pointer was expected and
     * `queue` stayed NULL with a success code. vkCreateDevice and
     * vkGetDeviceQueue are not shaped alike; copying one signature onto
     * the other is exactly the bug this note exists to prevent. */
    int (*GetDeviceQueue)(void *, unsigned, unsigned, void *);
    int (*DeviceWaitIdle)(void *);
  } vk;

  /* Loaded through the loader; the two proc-address resolvers bootstrap the
   * rest and are therefore kept separately from the table. */
  void *(*get_instance_proc_addr)(void *, const char *);
  void *(*get_device_proc_addr)(void *, const char *);
  bool surface_created;
};

#endif /* EZCORE_GPU_INTERNAL_H */
