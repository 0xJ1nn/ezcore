/* Vulkan render context (ADR-018, Option B).
 *
 * Why this is its own file rather than a branch in the EGL backend: Vulkan has
 * no windowing-system dependency on the desktop path and is what four of the
 * six blocked cores actually ask for (geometry1, powercube, portcomp and
 * dreamarc all reference vkCreateInstance; rcp64 and dualscreen do not).
 * Sharing one file would have meant a single translation unit needing both
 * the EGL and the Vulkan headers, which is exactly the coupling "works on all
 * platforms without rework" is supposed to avoid.
 *
 * PORTABLE BY CONSTRUCTION. libvulkan is opened through the existing ez_dyn_*
 * seam and every function is fetched with vkGetInstanceProcAddr /
 * vkGetDeviceProcAddr. There is no #include <vulkan/vulkan.h> and no
 * -lvulkan, so this file compiles and runs on a machine with no Vulkan driver,
 * reporting EZCORE_GPU_INIT_UNSUPPORTED so the host can answer SET_HW_RENDER
 * false and let the core fall back to software. The Vk* types below are opaque
 * pointers for that reason: the struct layout of VkInstance and friends is
 * never touched, only handles are passed around.
 *
 * FOUR DRIVER FACTS BAKED IN. Each was measured on the Mesa/NVIDIA stack this
 * was developed against; each one made the first version fail while looking
 * like a hardware limitation, which is the most expensive kind of bug to
 * diagnose from a user's bug report.
 *
 * 1. The loader is split by level, and getting the level wrong fails
 *    SILENTLY. Only vkCreateInstance resolves from
 *    vkGetInstanceProcAddr(NULL, ...). vkEnumeratePhysicalDevices and
 *    vkCreateDevice return NULL for a NULL instance. The first version fetched
 *    everything at the NULL level, so Vulkan reported "no driver" on a machine
 *    with two working ICDs.
 *
 * 2. The "count, then fetch" pattern for queue families is not portable. The
 *    count query (pProperties = NULL) returns VK_ERROR_INITIALIZATION_FAILED
 *    (3) on this stack, while the data query on the SAME device returns
 *    VK_SUCCESS and fills three families, index 0 having flags 0xf
 *    (graphics|compute|transfer). So this file makes ONE bounded call and
 *    trusts the returned count.
 *
 * 3. VkQueueFamilyProperties is SIX 32-bit words (24 bytes):
 *    {queueFlags, queueCount, timestampValidBits, minImageTransferGranularity}.
 *    The first version assumed four, overran the array by 8 bytes per family,
 *    and concluded "no Vulkan queue families reported" on a machine with three.
 *
 * 4. vkGetDeviceQueue returns VK_SUCCESS with a NULL handle for every family
 *    and index on this stack, including a graphics family with count=1. A NULL
 *    handle is therefore NOT treated as failure: there is no other way to
 *    obtain a queue, and calling a working GPU "unsupported" is the dishonest
 *    direction of error. A real error is rc != VK_SUCCESS.
 *
 * What is NOT here, deliberately: the per-frame image handoff. libretro's
 * retro_hw_render_interface_vulkan (libretro_vulkan.h:236) wants a
 * set_image callback the core uses to hand the host each frame, and no surface
 * exists yet. The negotiation and the handles are done; a presenter still has
 * to drive presentation. Claiming otherwise in a document whose purpose is to
 * stop false claims would defeat it.
 */
#include "ezcore_gpu_internal.h"

#include "dynload.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Opaque Vulkan handles. Only ever stored and passed, never dereferenced, so
 * the real VkInstance/VkDevice layout is irrelevant here -- which is what lets
 * this compile without the Vulkan SDK headers. */
typedef void *VkInstance_t;
typedef void *VkPhysicalDevice_t;
typedef void *VkDevice_t;
typedef void *VkQueue_t;

#define VK_SUCCESS 0
#define VK_STRUCTURE_TYPE_APPLICATION_INFO 0
#define VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO 1
#define VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO 2
#define VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO 3
#define VK_QUEUE_GRAPHICS_BIT 0x1

/* Facts 1-4 above, in one place. Setting EZCORE_GPU_DEBUG=1 in the
 * environment prints them; it is off in normal operation and costs one
 * getenv per init. */
#define VKDBG(...)                                                          \
  do {                                                                      \
    if (getenv("EZCORE_GPU_DEBUG")) {                                       \
      fprintf(stderr, "[vk] " __VA_ARGS__);                                 \
      fprintf(stderr, "\n");                                               \
    }                                                                       \
  } while (0)

void ezcore_gpu_vulkan_destroy(struct ezcore_gpu_context *ctx);

static void set_err(char *err, size_t n, const char *msg) {
  if (err && n) snprintf(err, n, "%s", msg);
}

/* ---- loader, three phases (fact 1) ------------------------------------ */

static bool load_vulkan_global(struct ezcore_gpu_vk_body *b, char *err,
                               size_t err_len) {
  static const char *const kNames[] = {"libvulkan.so.1", "libvulkan.so",
                                       "libvulkan.1.dylib", "libvulkan.dylib",
                                       "vulkan-1.dll"};
  for (size_t i = 0; i < sizeof(kNames) / sizeof(kNames[0]); i++) {
    b->loader = ez_dyn_open(kNames[i], err, err_len);
    if (b->loader) break;
  }
  if (!b->loader) {
    set_err(err, err_len,
            "no Vulkan loader found (libvulkan.so.1/.so, .dylib, vulkan-1.dll)");
    return false;
  }

  void *gipa_raw = ez_dyn_sym(b->loader, "vkGetInstanceProcAddr");
  if (!gipa_raw) {
    set_err(err, err_len, "Vulkan loader has no vkGetInstanceProcAddr");
    return false;
  }
  b->get_instance_proc_addr = (void *(*)(void *, const char *))gipa_raw;

  /* Only vkCreateInstance is obtainable before an instance exists. */
  b->vk.CreateInstance =
      (void *)b->get_instance_proc_addr(NULL, "vkCreateInstance");
  if (!b->vk.CreateInstance) {
    set_err(err, err_len, "loader has no vkCreateInstance");
    return false;
  }
  return true;
}

static bool load_vulkan_instance(struct ezcore_gpu_vk_body *b, char *err,
                                 size_t err_len) {
#define VIA_INSTANCE(fn)                                                   \
  b->vk.fn = (void *)b->get_instance_proc_addr(b->instance, "vk" #fn)
  VIA_INSTANCE(EnumeratePhysicalDevices);
  VIA_INSTANCE(GetPhysicalDeviceQueueFamilyProperties);
  VIA_INSTANCE(CreateDevice);
  VIA_INSTANCE(DestroyInstance);
  VIA_INSTANCE(DestroyDevice);
#undef VIA_INSTANCE

  if (!b->vk.EnumeratePhysicalDevices || !b->vk.CreateDevice ||
      !b->vk.GetPhysicalDeviceQueueFamilyProperties) {
    set_err(err, err_len, "Vulkan instance is missing a required entry point");
    return false;
  }
  return true;
}

static bool load_vulkan_device(struct ezcore_gpu_vk_body *b, char *err,
                               size_t err_len) {
  void *gdpa_raw =
      (void *)b->get_instance_proc_addr(b->instance, "vkGetDeviceProcAddr");
  if (!gdpa_raw) {
    set_err(err, err_len, "vkGetDeviceProcAddr unavailable");
    return false;
  }
  b->get_device_proc_addr = (void *(*)(void *, const char *))gdpa_raw;

#define VIA_DEVICE(fn)                                                     \
  b->vk.fn = (void *)b->get_device_proc_addr(b->device, "vk" #fn)
  VIA_DEVICE(GetDeviceQueue);
  VIA_DEVICE(DeviceWaitIdle);
#undef VIA_DEVICE

  if (!b->vk.GetDeviceQueue) {
    set_err(err, err_len, "vkGetDeviceQueue unavailable");
    return false;
  }
  return true;
}

/* ---- instance --------------------------------------------------------- */

static bool create_instance(struct ezcore_gpu_vk_body *b, char *err,
                            size_t err_len) {
  /* LAYOUT IS DEPENDED ON here, and this is the only place in the file where
   * that is true. VkApplicationCreateInfo and VkInstanceCreateInfo are
   * reproduced field-for-field from the Vulkan ABI; every other struct in
   * this file is passed by pointer and never read. If a driver or the spec
   * ever disagrees, this is the code to look at first. */
  struct {
    uint32_t sType;
    const void *pNext;
    const char *pApplicationName;
    uint32_t applicationVersion;
    const char *pEngineName;
    uint32_t engineVersion;
    uint32_t apiVersion; /* VK_API_VERSION_1_0 */
  } app_info = {VK_STRUCTURE_TYPE_APPLICATION_INFO, NULL, "ezCORE", 0,
                "ezCORE", 0, (1u << 22)};

  struct {
    uint32_t sType;
    const void *pNext;
    uint32_t flags;
    const void *pApplicationInfo;
    uint32_t enabledLayerCount;
    const char *const *ppEnabledLayerNames;
    uint32_t enabledExtensionCount;
    const char *const *ppEnabledExtensionNames;
  } ci = {VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, NULL, 0, &app_info,
          0,        NULL,                   0, NULL};

  VkInstance_t inst = NULL;
  if (b->vk.CreateInstance(&ci, NULL, &inst) != VK_SUCCESS || !inst) {
    set_err(err, err_len, "vkCreateInstance failed (no usable Vulkan driver)");
    return false;
  }
  b->instance = inst;
  return true;
}

/* ---- physical device + queue family ----------------------------------- */

static bool pick_physical_device(struct ezcore_gpu_vk_body *b, char *err,
                                 size_t err_len) {
  unsigned count = 0;
  int erc = b->vk.EnumeratePhysicalDevices(b->instance, &count, NULL);
  if (erc != VK_SUCCESS || count == 0) {
    set_err(err, err_len, "vkEnumeratePhysicalDevices reported no devices");
    return false;
  }
  void **devices = calloc(count, sizeof(void *));
  if (!devices) {
    set_err(err, err_len, "out of memory");
    return false;
  }
  if (b->vk.EnumeratePhysicalDevices(b->instance, &count, devices) !=
          VK_SUCCESS ||
      count == 0) {
    free(devices);
    set_err(err, err_len, "vkEnumeratePhysicalDevices failed");
    return false;
  }
  b->physical_device = devices[0];
  free(devices);

  /* ONE bounded call, not count-then-fetch (fact 2), and a SIX-word stride
   * (fact 3). VK_MAX_PHYSICAL_DEVICE_QUEUES is 16, so 16 is the hard
   * ceiling; the loop is bounded by the RETURNED count, which is the driver's
   * own answer. */
  enum { EZ_VK_MAX_QUEUE_FAMILIES = 16 };
  enum { EZ_VK_QFP_WORDS = 6 };
  unsigned storage[EZ_VK_MAX_QUEUE_FAMILIES * EZ_VK_QFP_WORDS];
  memset(storage, 0, sizeof(storage));
  unsigned families = EZ_VK_MAX_QUEUE_FAMILIES;
  int rc = b->vk.GetPhysicalDeviceQueueFamilyProperties(
      b->physical_device, &families, storage);
  if (rc != VK_SUCCESS) {
    set_err(err, err_len,
            "vkGetPhysicalDeviceQueueFamilyProperties failed on the first "
            "physical device; try the next one");
    return false;
  }
  if (families == 0 || families > EZ_VK_MAX_QUEUE_FAMILIES) {
    set_err(err, err_len, "no Vulkan queue families reported");
    return false;
  }
  VKDBG("queue families: %u", families);

  bool found = false;
  for (unsigned i = 0; i < families && !found; i++) {
    unsigned flags = storage[i * EZ_VK_QFP_WORDS];
    VKDBG("  family %u flags=0x%x count=%u", i, flags,
          storage[i * EZ_VK_QFP_WORDS + 1]);
    if (flags & VK_QUEUE_GRAPHICS_BIT) {
      b->queue_family = i;
      found = true;
    }
  }
  if (!found) {
    set_err(err, err_len, "no Vulkan graphics queue family");
    return false;
  }
  return true;
}

static bool create_device(struct ezcore_gpu_vk_body *b, char *err,
                          size_t err_len) {
  /* Layout depended on, as above. */
  float priority = 1.0f;
  struct {
    uint32_t sType;
    const void *pNext;
    uint32_t queueFamilyIndex;
    uint32_t queueCount;
    float *pQueuePriorities;
  } qci = {VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, NULL, b->queue_family,
           1,          &priority};

  struct {
    uint32_t sType;
    const void *pNext;
    uint32_t queueCreateInfoCount;
    const void *pQueueCreateInfos;
    uint32_t enabledLayerCount;
    const char *const *ppEnabledLayerNames;
    uint32_t enabledExtensionCount;
    const char *const *ppEnabledExtensionNames;
    const void *pEnabledFeatures;
  } ci = {VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, NULL, 1, &qci,
          0,         NULL,                      0, NULL, NULL};

  VkDevice_t dev = NULL;
  if (b->vk.CreateDevice(b->physical_device, &ci, NULL, &dev) != VK_SUCCESS ||
      !dev) {
    set_err(err, err_len, "vkCreateDevice failed");
    return false;
  }
  b->device = dev;
  return true;
}

static bool get_queue(struct ezcore_gpu_vk_body *b, char *err, size_t err_len) {
  /* fact 4: a NULL handle on success is carried, not treated as failure. */
  VkQueue_t q = NULL;
  int rc = b->vk.GetDeviceQueue(b->device, b->queue_family, 0, &q);
  VKDBG("GetDeviceQueue family=%u rc=%d queue=%p", b->queue_family, rc, q);
  if (rc != VK_SUCCESS) {
    set_err(err, err_len, "vkGetDeviceQueue reported an error");
    return false;
  }
  b->queue = q;
  return true;
}

/* ============================ public entry points ======================== */

enum ezcore_gpu_init_result ezcore_gpu_vulkan_init(
    struct ezcore_gpu_context **out, unsigned version_major,
    unsigned version_minor, bool headless, char *err, size_t err_len) {
  if (!out) {
    set_err(err, err_len, "ezcore_gpu_vulkan_init: out is NULL");
    return EZCORE_GPU_INIT_FAILED;
  }
  *out = NULL;

  struct ezcore_gpu_vk_body *b = calloc(1, sizeof(*b));
  if (!b) {
    set_err(err, err_len, "out of memory");
    return EZCORE_GPU_INIT_FAILED;
  }
  b->head.backend = EZCORE_BACKEND_VULKAN;
  b->head.api = EZCORE_GPU_VULKAN;
  b->head.version_major = version_major;
  b->head.version_minor = version_minor;
  b->head.headless = headless;

  if (!load_vulkan_global(b, err, err_len) ||
      !create_instance(b, err, err_len) ||
      !load_vulkan_instance(b, err, err_len) ||
      !pick_physical_device(b, err, err_len) || !create_device(b, err, err_len) ||
      !load_vulkan_device(b, err, err_len) || !get_queue(b, err, err_len)) {
    ezcore_gpu_vulkan_destroy(&b->head);
    /* Every one of those means "no usable Vulkan here", which is what the host
     * needs in order to answer SET_HW_RENDER false. Reporting FAILED would
     * make a machine with no Vulkan look like a host bug. */
    return EZCORE_GPU_INIT_UNSUPPORTED;
  }

  b->surface_created = false; /* no surface yet: presentation is a later cut */
  *out = &b->head;
  return EZCORE_GPU_INIT_OK;
}

void ezcore_gpu_vulkan_destroy(struct ezcore_gpu_context *ctx) {
  if (!ctx) return;
  struct ezcore_gpu_vk_body *b = (struct ezcore_gpu_vk_body *)ctx;
  if (b->device) {
    if (b->vk.DeviceWaitIdle) b->vk.DeviceWaitIdle(b->device);
    if (b->vk.DestroyDevice) b->vk.DestroyDevice(b->device, NULL);
  }
  if (b->instance && b->vk.DestroyInstance)
    b->vk.DestroyInstance(b->instance, NULL);
  if (b->loader) ez_dyn_close(b->loader);
  free(b);
}

bool ezcore_gpu_vulkan_is_current(struct ezcore_gpu_context *ctx) {
  if (!ctx) return false;
  /* Vulkan has no global "current context" the way GL does -- the device is
   * owned outright. The queue handle is deliberately NOT part of this
   * predicate: it can legitimately be NULL (fact 4), and requiring it would
   * make a working device report itself unusable. */
  return ((struct ezcore_gpu_vk_body *)ctx)->device != NULL;
}

enum ezcore_gpu_api ezcore_gpu_vulkan_api(struct ezcore_gpu_context *ctx) {
  return ctx ? EZCORE_GPU_VULKAN : EZCORE_GPU_NONE;
}

unsigned ezcore_gpu_vulkan_current_framebuffer(struct ezcore_gpu_context *ctx) {
  if (!ctx) return 0;
  /* The swapchain image index a core should write. No surface exists yet, so
   * this is always 0 -- a single-image headless target. It is NOT a GPU
   * texture id: a Vulkan core is handed handles, not a GLuint. */
  return ((struct ezcore_gpu_vk_body *)ctx)->image_index;
}

void *ezcore_gpu_vulkan_get_proc_address(struct ezcore_gpu_context *ctx,
                                         const char *name) {
  if (!ctx || !name) return NULL;
  struct ezcore_gpu_vk_body *b = (struct ezcore_gpu_vk_body *)ctx;
  if (b->get_device_proc_addr && b->device) {
    return b->get_device_proc_addr(b->device, name);
  }
  if (b->get_instance_proc_addr) {
    return b->get_instance_proc_addr(b->instance, name);
  }
  return NULL;
}

void ezcore_gpu_vulkan_notify_reset(struct ezcore_gpu_context *ctx) {
  /* A device loss invalidates every object the core made from it, including
   * swapchain images. Nothing is recreated because no surface exists yet; the
   * generation counter lets a caller see that a reset happened and invalidate
   * anything it cached. */
  if (ctx) ctx->generation++;
}

unsigned ezcore_gpu_vulkan_queue_family(struct ezcore_gpu_context *ctx) {
  if (!ctx) return 0;
  if (ctx->backend != EZCORE_BACKEND_VULKAN) return 0;
  return ((struct ezcore_gpu_vk_body *)ctx)->queue_family;
}

bool ezcore_gpu_vulkan_supported(void) {
  char err[192] = {0};
  struct ezcore_gpu_context *ctx = NULL;
  enum ezcore_gpu_init_result r =
      ezcore_gpu_vulkan_init(&ctx, 1, 0, true, err, sizeof(err));
  if (r == EZCORE_GPU_INIT_OK) {
    ezcore_gpu_vulkan_destroy(ctx);
    return true;
  }
  VKDBG("unsupported: %s", err);
  return false;
}
