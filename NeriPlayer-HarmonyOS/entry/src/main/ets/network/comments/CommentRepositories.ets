/**
 * 评论仓库工厂（上游 AppContainer.commentRepositoryFor 的鸿蒙等价）：
 * 全局共享一个 CommentMemoryCache（五分钟 TTL + LRU），按平台分发仓库。
 */
import { CommentPlatform } from '../../model/CommentModels';
import { CommentMemoryCache, CommentRepository } from './CommentRepositoryCore';
import { NeteaseCommentRepository, LiveNeteaseCommentClientDeps } from './NeteaseCommentRepository';
import { BiliCommentRepository, LiveBiliCommentClientDeps } from './BiliCommentRepository';

const sharedCommentCache: CommentMemoryCache = new CommentMemoryCache();
const neteaseComments: NeteaseCommentRepository =
  new NeteaseCommentRepository(sharedCommentCache, new LiveNeteaseCommentClientDeps());
const biliComments: BiliCommentRepository =
  new BiliCommentRepository(sharedCommentCache, new LiveBiliCommentClientDeps());

export function commentRepositoryFor(platform: CommentPlatform): CommentRepository {
  return platform === CommentPlatform.BILIBILI ? biliComments : neteaseComments;
}
