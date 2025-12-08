#include "RNOH/PackageProvider.h"
#include "SafeAreaViewPackage.h"
#include "generated/RNOHGeneratedPackage.h"
#include "AsyncStoragePackage.h"
#include "WebViewPackage.h"
#include "CookiesPackage.h"

using namespace rnoh;

std::vector<std::shared_ptr<Package>> PackageProvider::getPackages(Package::Context ctx) {
    return {
        std::make_shared<SafeAreaViewPackage>(ctx),
        std::make_shared<RNOHGeneratedPackage>(ctx),
        std::make_shared<AsyncStoragePackage>(ctx),
        std::make_shared<WebViewPackage>(ctx),
        std::make_shared<CookiesPackage>(ctx),
    };
}