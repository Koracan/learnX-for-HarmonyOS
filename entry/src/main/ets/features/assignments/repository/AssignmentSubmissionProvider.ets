/*
 * 作业提交的组装点（composition root）。
 *
 * 与 data/notices、data/courses 的 provider 同一形状：把 `AuthedTaskRunner`（重登 + 只重试一次
 * + 显式降级）显式适配成提交用例要的执行器端口，**这里不重新实现重登 / 重试 / 降级**。
 *
 * 三个零件：
 *   - `HttpFetchPort`：真正发 multipart；
 *   - `DeviceAttachmentReader`：把 picker 给的 URI 读成字节；
 *   - `AssignmentSubmitter`：早退分支 + 把一次提交包成会话任务。
 *
 * ## 两条出口（Mock 模式）
 *
 * `createAssignmentSubmitter()` 按 `isMockMode()` 分支：mock 模式返回
 * `data/mock/MockAssignmentSubmitter`（本地样例提交，**零网络**），否则走上面的真实装配。
 * 两条分支**共用同一个** `DeviceAttachmentReader`（mock 那条也把附件字节读进台账：
 * 用户刚提交的附件随后必须真的打得开，见 data/mock/MockSubmissionJournal 的文件头）。
 * 这是 Mock 开关的第四个消费点（notice / course / file 三条线在各自的 provider 里已有同形分支）；
 * 在它存在之前，mock 账号没有会话，提交必然降级成"需要重新验证"，界面一律弹「提交失败」。
 *
 * 判据只有 `features/mock/MockMode` 一处，界面（`AssignmentSubmissionPage`）不知道 mock 的存在。
 * 装配点每次打一行日志说清选了哪条，并带上 `describeMockMode()` 与网络请求数（消费点自证）。
 */
import { Logger } from '../../../core/log/Logger';
import { authServices } from '../../auth/AuthServices';
import { AuthedRunResult, AuthedTaskRunner, SessionTask } from '../../../data/auth/SessionRestore';
import { HttpFetchPort } from '../../../data/remote/HttpFetchPort';
import {
  AssignmentSubmitter, AttachmentBytesSource, AuthedTaskExecutor, SubmitAssignment
} from '../../../data/assignments/SubmitAssignment';
import { DeviceAttachmentReader } from '../../../data/assignments/DeviceAttachmentReader';
import { MockAssignmentSubmitter } from '../../../data/mock/MockAssignmentSubmitter';
import { networkAttemptCount } from '../../../data/remote/NetworkAudit';
import { describeMockMode, isMockMode } from '../../mock/MockMode';

const LOG_DOMAIN: string = 'data.assignments.submit';

/**
 * 当前生效的提交出口。
 *
 * `logger` 只用于**装配点自证**（说清选了哪条）；下面真实那条装配的三个零件仍各自带
 * 自己的 `Logger` —— 既有装配行保持原样，不因为加了一行日志而改动它们。
 */
export function createAssignmentSubmitter(): AssignmentSubmitter {
  const logger: Logger = new Logger(LOG_DOMAIN);
  // Mock 模式：本地样例提交出口，**一个字节都不发**。判据只有 features/mock/MockMode 一处。
  // 附件读取器两条分支共用：mock 的本地提交也要读**真实的**选中字节（读不到就不写附件）。
  const reader: AttachmentBytesSource = new DeviceAttachmentReader(new Logger(LOG_DOMAIN));
  if (isMockMode()) {
    logger.info('assignment submitter wired: source=mock (guest mode, zero network) '
      + describeMockMode() + ' networkAttempts=' + networkAttemptCount().toString());
    return new MockAssignmentSubmitter(logger, reader);
  }
  const port: HttpFetchPort = new HttpFetchPort();
  const useCase: SubmitAssignment = new SubmitAssignment(port, reader, new Logger(LOG_DOMAIN));
  const executor: AuthedTaskExecutor = new RunnerTaskExecutor(authServices.runner);
  logger.info('assignment submitter wired: source=real (http multipart via AuthedTaskRunner) '
    + describeMockMode() + ' networkAttempts=' + networkAttemptCount().toString());
  return new AssignmentSubmitter(executor, useCase, new Logger(LOG_DOMAIN));
}

/**
 * 把 `AuthedTaskRunner` 显式适配成 `AuthedTaskExecutor`。
 *
 * 为什么不直接赋值：ArkTS 不做结构类型（arkts-no-structural-typing），两个形状相同的接口
 * 也不能互相赋值（实测）。适配器只有一行转发，并让「数据路径只经过
 * AuthedTaskRunner」这件事在类型上可见。
 */
class RunnerTaskExecutor implements AuthedTaskExecutor {
  private readonly runner: AuthedTaskRunner;

  constructor(runner: AuthedTaskRunner) {
    this.runner = runner;
  }

  run(task: SessionTask): Promise<AuthedRunResult> {
    return this.runner.run(task);
  }
}
