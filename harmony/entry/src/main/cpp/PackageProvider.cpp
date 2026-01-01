#include "RNOH/PackageProvider.h"
#include "SafeAreaViewPackage.h"
#include "generated/RNOHGeneratedPackage.h"
#include "AsyncStoragePackage.h"
#include "WebViewPackage.h"
#include "CookiesPackage.h"
#include "GestureHandlerPackage.h"
#include "BlobUtilPackage.h"
#include "FsPackage.h"
#include "LocalizePackage.h"
#include "ViewPagerPackage.h"
#include "PdfViewPackage.h"
#include "ReanimatedPackage.h"
#include "RNSharePackage.h"
#include "RTNSecureKeyStorePackage.h"
#include "SecureRandomPackage.h"
#include "RNImmersivePackage.h"
#include "FileViewerPackage.h"
#include "DocumentPickerPackage.h"
#include "RNImagePickerPackage.h"

using namespace rnoh;

std::vector<std::shared_ptr<Package>> PackageProvider::getPackages(Package::Context ctx) {
    return {
        std::make_shared<SafeAreaViewPackage>(ctx),
        std::make_shared<RNOHGeneratedPackage>(ctx),
        std::make_shared<AsyncStoragePackage>(ctx),
        std::make_shared<WebViewPackage>(ctx),
        std::make_shared<CookiesPackage>(ctx),
        std::make_shared<GestureHandlerPackage>(ctx),
        std::make_shared<BlobUtilPackage>(ctx),
        std::make_shared<FsPackage>(ctx),
        std::make_shared<LocalizePackage>(ctx),
        std::make_shared<ViewPagerPackage>(ctx),
        std::make_shared<PdfViewPackage>(ctx),
        std::make_shared<ReanimatedPackage>(ctx),
        std::make_shared<RNSharePackage>(ctx),
        std::make_shared<RTNSecureKeyStorePackage>(ctx),
        std::make_shared<SecureRandomPackage>(ctx),
        std::make_shared<RNImmersivePackage>(ctx),
        std::make_shared<FileViewerPackage>(ctx),
        std::make_shared<DocumentPickerPackage>(ctx),
        std::make_shared<RNImagePickerPackage>(ctx),
    };
}