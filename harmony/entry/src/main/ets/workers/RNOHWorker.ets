import { setupRNOHWorker } from "@rnoh/react-native-openharmony/src/main/ets/setupRNOHWorker";
import { createRNPackages } from '../RNPackagesFactory';

setupRNOHWorker({
  createWorkerRNInstanceConfig: (rnInstanceName) => {
    return {
      thirdPartyPackagesFactory: createRNPackages,
    }
  }
})