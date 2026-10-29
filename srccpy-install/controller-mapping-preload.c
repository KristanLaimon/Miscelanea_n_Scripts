// Loads an SDL mapping specified by SCRCPY_CONTROLLER_MAPPING right after
// scrcpy initializes SDL. scrcpy does not explicitly initialize SDL_GAMEPAD,
// which is why SDL_GAMECONTROLLERCONFIG_FILE comes too late.

#include <SDL3/SDL.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

typedef bool (*sdl_init_function)(SDL_InitFlags flags);

bool
SDL_Init(SDL_InitFlags flags) {
    static sdl_init_function real_sdl_init;

    if (!real_sdl_init) {
        real_sdl_init = (sdl_init_function) dlsym(RTLD_NEXT, "SDL_Init");
        if (!real_sdl_init) {
            fputs("scrcpy controller mapping: SDL_Init not found\n", stderr);
            return false;
        }
    }

    bool ok = real_sdl_init(flags);
    if (!ok) {
        return false;
    }

    const char *mapping = getenv("SCRCPY_CONTROLLER_MAPPING");
    if (mapping && *mapping && SDL_AddGamepadMapping(mapping) < 0) {
        fprintf(stderr, "scrcpy controller mapping: %s\n", SDL_GetError());
    }

    return true;
}
