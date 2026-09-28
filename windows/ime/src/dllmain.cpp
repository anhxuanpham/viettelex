// dllmain.cpp — DLL entry points and the class factory. DllMain does nothing but
// remember the module handle (no threads, no I/O — spec §10).
#include <new>

#include "globals.h"
#include "text_service.h"

namespace vtx::tip {
HRESULT RegisterServer();
HRESULT UnregisterServer();

namespace {

class ClassFactory final : public IClassFactory {
public:
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_INVALIDARG;
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_IClassFactory)) {
            *ppv = static_cast<IClassFactory*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    // Static object: lifetime is the DLL's; LockServer/refcount keep the DLL loaded.
    STDMETHODIMP_(ULONG) AddRef() override {
        DllAddRef();
        return 2;
    }
    STDMETHODIMP_(ULONG) Release() override {
        DllRelease();
        return 1;
    }
    STDMETHODIMP CreateInstance(IUnknown* outer, REFIID riid, void** ppv) override {
        return TextService::CreateInstance(outer, riid, ppv);
    }
    STDMETHODIMP LockServer(BOOL lock) override {
        if (lock) DllAddRef();
        else DllRelease();
        return S_OK;
    }
};

ClassFactory g_factory;

}  // namespace
}  // namespace vtx::tip

using namespace vtx::tip;

extern "C" BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_hInst = inst;
        DisableThreadLibraryCalls(inst);
    }
    return TRUE;
}

extern "C" HRESULT __stdcall DllGetClassObject(REFCLSID clsid, REFIID riid, void** ppv) {
    if (!ppv) return E_INVALIDARG;
    *ppv = nullptr;
    if (!IsEqualCLSID(clsid, CLSID_VietTelexTIP)) return CLASS_E_CLASSNOTAVAILABLE;
    return g_factory.QueryInterface(riid, ppv);
}

extern "C" HRESULT __stdcall DllCanUnloadNow() {
    if (g_dllRefCount > 0) return S_FALSE;
    // About to be unloaded: drop the text-tool window class (outside the loader lock; its
    // name is unique per module load, so even a missed unregister can never hand a later
    // load a stale window procedure — see TextService::createToolWindow).
    UnregisterToolWindowClass();
    return S_OK;
}

extern "C" HRESULT __stdcall DllRegisterServer() {
    HRESULT hr = RegisterServer();
    if (FAILED(hr)) UnregisterServer();
    return hr;
}

extern "C" HRESULT __stdcall DllUnregisterServer() { return UnregisterServer(); }
