/* ezcore_core_host_protocol.h — the wire contract between ezCORE and
 * ezcore_core_host, the helper process that runs one core session (P6,
 * ADR-015).
 *
 * This is NOT a core ABI. Cores still speak libretro and know nothing about
 * it; this is how the *app* talks to the process that hosts a core, so a
 * crash in the core kills that process instead of the app.
 *
 * Framing, both directions, all integers little-endian:
 *
 *   u32 length   bytes that follow (never 0)
 *   ...          `length` bytes of body
 *
 * Request body:  u8 op, then the op's arguments.
 * Response body: u8 status (EZH_OK / EZH_ERROR), then the op's results;
 *                on EZH_ERROR the rest is a UTF-8 message (no length prefix).
 *
 * Strings are u32 byte length + UTF-8 bytes (no terminator). Byte blobs are
 * u32 length + bytes.
 *
 * Ops (arguments -> results on EZH_OK):
 *   OPEN       str core, str content, str system_dir, str save_dir,
 *              u32 n, n x (str key, str value)
 *              -> str core_name, u32 w, u32 h, f64 fps, f64 sample_rate,
 *                 u32 n_rejected, n_rejected x str key
 *   FRAME      u32 count (1..8)
 *              -> u8 has_frame; if 1: u32 w, u32 h, blob rgba, blob pcm
 *                 (pcm is s16 stereo; empty when count > 1 or paused)
 *   PAUSE      u8 paused               -> (nothing)
 *   BUTTON     u32 port, u32 id, u8 pressed -> (nothing)
 *   SAVE       (none)                  -> blob state
 *   RESTORE    blob state              -> (nothing)
 *   CHEATS     u32 n, n x (u32 index, u8 enabled, str code)
 *              -> u32 n_failed, n_failed x u32 index
 *   RESET      (none)                  -> (nothing)
 *   OPTIONS    (none)                  -> u32 n, n x (str key, str default,
 *                                         str value)
 *   SET_OPTION str key, str value      -> u8 matched
 *   CLOSE      (none)                  -> (nothing); the host then exits 0
 *
 * The host exits 0 when its input reaches EOF (the app went away), so it
 * never outlives the app. A core crash kills the host; the app sees EOF on
 * the response stream and reads the exit status to classify it.
 */
#ifndef EZCORE_CORE_HOST_PROTOCOL_H
#define EZCORE_CORE_HOST_PROTOCOL_H

#define EZH_PROTOCOL_VERSION 1

#define EZH_OK 0
#define EZH_ERROR 1

#define EZH_OP_OPEN 1
#define EZH_OP_FRAME 2
#define EZH_OP_PAUSE 3
#define EZH_OP_BUTTON 4
#define EZH_OP_SAVE 5
#define EZH_OP_RESTORE 6
#define EZH_OP_CHEATS 7
#define EZH_OP_RESET 8
#define EZH_OP_OPTIONS 9
#define EZH_OP_SET_OPTION 10
#define EZH_OP_CLOSE 11

/* Never sent by the app; lets the tests prove an unknown op is an error. */
#define EZH_OP_BOGUS_FOR_TEST 250

/* Largest request body the host accepts (a save state is the big one). */
#define EZH_MAX_REQUEST (256u * 1024u * 1024u)

#endif
