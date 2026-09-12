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
 */
import { Logger } from '../../../core/log/Logger';
import { authServices } from '../../auth/AuthServices';
import { AuthedRunResult, AuthedTaskRunner, SessionTask } from '../../../data/auth/SessionRestore';
import { HttpFetchPort } from '../../../data/remote/HttpFetchPort';
import {
  AssignmentSubmitter, AttachmentBytesSource, AuthedTaskExecutor, SubmitAssignment
} from '../../../data/assignments/SubmitAssignment';
import { DeviceAttachmentReader } from '../../../data/assignments/DeviceAttachmentReader';

const LOG_DOMAIN: string = 'data.assignments.submit';

/** 当前生效的提交出口。 */
export function createAssignmentSubmitter(): AssignmentSubmitter {
  const port: HttpFetchPort = new HttpFetchPort();
  const reader: AttachmentBytesSource = new DeviceAttachmentReader(new Logger(LOG_DOMAIN));
  const useCase: SubmitAssignment = new SubmitAssignment(port, reader, new Logger(LOG_DOMAIN));
  const executor: AuthedTaskExecutor = new RunnerTaskExecutor(authServices.runner);
  return new AssignmentSubmitter(executor, useCase, new Logger(LOG_DOMAIN));
}

/**
 * 把 `AuthedTaskRunner` 显式适配成 `AuthedTaskExecutor`。
 *
 * 为什么不直接赋值：ArkTS 不做结构类型（arkts-no-structural-typing），两个形状相同的接口
 * 也不能互相赋值（ticket 09 实测）。适配器只有一行转发，并让「数据路径只经过
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
