#pragma once

// Compatibility shim for modern MSVC/Windows SDK builds.
//
// windows.h exposes a GetObject macro that expands RapidJSON's
// Value::GetObject() calls into Value::GetObjectA(), causing compilation
// failures in files such as light.cpp and init_game.cpp. Include WinSock2
// before windows.h, then remove only the conflicting macro.

#if defined(_WIN32)

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <WinSock2.h>
#include <windows.h>

#ifdef GetObject
#undef GetObject
#endif

#endif // defined(_WIN32)
