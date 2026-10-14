/**
 * 评论面板（上游 ui/component/comment/CommentSheet 家族的鸿蒙移植，#476
 * 三态面板 + 楼中楼 + 点赞）。宿主用原生 bindSheet 承载（与队列面板同款）；
 * 状态经 AppStorage 的 'ui.commentPanelState' 快照广播（@StorageProp 引用
 * 传递，避免整状态 JSON 序列化），评论来源经 'ui.commentSource'（JSON）。
 * B 站点赞/发评完整支持；网易侧因上游易盾设备校验缺失只读（可浏览、不可
 * 互动），与 canInteractWithComments 的判定一致。
 */
import { CommentPlatform, CommentSort, CommentError, CommentReplyTarget, CommentQuote, CommentImage, SongComment, commentSortsSupportedBy, commentLengthLimit } from '../../../model/CommentModels';
import { CommentPanelController, CommentPanelUiState, CommentReplyPanelState, CommentListStatus } from './CommentPanelController';
import { buildCommentSegments, formatCommentTime, CommentTextSegment } from './CommentPanelLogic';
import { SongCommentCodec, CommentSourceCodec, CommentReplyTargetJson, CommentReplyPanelStateCodec } from './CommentCodec';
import { Theme } from '../../Theme';

const APP_KEY_COMMENT_STATE: string = 'ui.commentPanelState';

export function commentErrorText(error: CommentError): string {
  switch (error) {
    case CommentError.NETWORK:
      return '网络不可用，请检查连接后重试';
    case CommentError.PERMISSION:
      return '需要登录后才能操作（网易评论互动暂不支持）';
    case CommentError.NOT_FOUND:
      return '资源不存在或已被删除';
    case CommentError.CLOSED:
      return '评论区已关闭';
    case CommentError.SERVER:
      return '平台服务暂时不可用，请稍后再试';
    case CommentError.API:
      return '评论接口暂时不可用，请稍后再试';
    default:
      return '评论加载失败，请重试';
  }
}

function commentSortLabel(sort: CommentSort): string {
  if (sort === CommentSort.NEWEST) {
    return '最新';
  }
  return sort === CommentSort.RECOMMENDED ? '推荐' : '热门';
}

/** 平台写能力：B 站点赞/发评完整支持；网易依赖上游网页端设备校验，只读。 */
export function canInteractWithComments(platform: CommentPlatform): boolean {
  return platform === CommentPlatform.BILIBILI;
}

@Component
export struct CommentSheetContent {
  @StorageProp('ui.commentSource') @Watch('onSourceKeyChanged')
  commentSourceJson: string = '';
  @StorageProp('ui.commentPanelState')
  panelState: CommentPanelUiState = new CommentPanelUiState();
  private controller: CommentPanelController | null = null;

  aboutToAppear(): void {
    this.controller = new CommentPanelController();
    this.controller.onChanged = (): void => {
      if (this.controller !== null) {
        AppStorage.setOrCreate(APP_KEY_COMMENT_STATE, this.controller.state);
      }
    };
    this.applySource();
  }

  aboutToDisappear(): void {
    if (this.controller !== null) {
      this.controller.onSheetHidden();
      this.controller = null;
    }
  }

  private applySource(): void {
    const source = CommentSourceCodec.fromJson(this.commentSourceJson);
    if (this.controller !== null) {
      this.controller.onSourceChanged(source);
    }
  }

  onSourceKeyChanged(): void {
    // 面板打开期间切歌：直接换绑评论来源（同源时控制器内部会去重）。
    this.applySource();
  }

  private sortActive(sort: CommentSort): boolean {
    return sort === (this.panelState.pendingSort ?? this.panelState.sort);
  }

  private platform(): CommentPlatform {
    return this.panelState.source !== null ? this.panelState.source.platform : CommentPlatform.NETEASE;
  }

  private canInteract(): boolean {
    return canInteractWithComments(this.platform());
  }

  private replyThreadJson(rootId: string): string {
    const thread = this.panelState.replyThreads.get(rootId);
    if (thread === undefined) {
      return '';
    }
    return CommentReplyPanelStateCodec.toJson(thread);
  }

  @Builder
  sortChips() {
    Row({ space: 8 }) {
      ForEach(commentSortsSupportedBy(this.platform()), (sort: CommentSort) => {
        Text(commentSortLabel(sort))
          .fontSize(13)
          .fontColor(this.sortActive(sort) ? Theme.primary(false) : Theme.textSecondary(Theme.isDark()))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(12)
          .backgroundColor(this.sortActive(sort)
            ? Theme.withAlpha(Theme.primary(false), 0.12) : Theme.surfaceVariant(Theme.isDark()))
          .onClick(() => {
            if (this.controller !== null) {
              this.controller.selectSort(sort);
            }
          })
      }, (sort: CommentSort) => `${sort}`)
    }
  }

  @Builder
  centeredNotice(icon: Resource, text: string, retryLabel: string, loading: boolean) {
    Column({ space: 12 }) {
      if (loading) {
        LoadingProgress().width(34).height(34).color(Theme.textSecondary(Theme.isDark()))
      } else {
        SymbolGlyph(icon)
          .fontSize(34)
          .fontColor([Theme.textSecondary(Theme.isDark())])
      }
      Text(text)
        .fontSize(14)
        .fontColor(Theme.textSecondary(Theme.isDark()))
        .textAlign(TextAlign.Center)
      if (retryLabel.length > 0) {
        Button(retryLabel)
          .fontSize(14)
          .height(34)
          .backgroundColor(Theme.primary(false))
          .onClick(() => {
            if (this.controller !== null) {
              this.controller.retry();
            }
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  likeErrorBanner() {
    Row({ space: 8 }) {
      Text(commentErrorText(this.panelState.likeError as CommentError))
        .fontSize(12)
        .fontColor(Theme.textSecondary(Theme.isDark()))
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(12)
        .fontColor([Theme.textSecondary(Theme.isDark())])
        .onClick(() => {
          if (this.controller !== null) {
            this.controller.dismissLikeError();
          }
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .borderRadius(10)
    .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
    .margin({ bottom: 8 })
  }

  @Builder
  loadErrorBanner() {
    Row({ space: 8 }) {
      Text(commentErrorText(this.panelState.error as CommentError))
        .fontSize(12)
        .fontColor(Theme.textSecondary(Theme.isDark()))
        .layoutWeight(1)
      Text('重试')
        .fontSize(12)
        .fontColor(Theme.primary(false))
        .onClick(() => {
          if (this.controller !== null) {
            this.controller.refresh();
          }
        })
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(12)
        .fontColor([Theme.textSecondary(Theme.isDark())])
        .onClick(() => {
          if (this.controller !== null) {
            this.controller.dismissLoadError();
          }
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .borderRadius(10)
    .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
    .margin({ bottom: 8 })
  }

  build() {
    Column() {
      // 标题 + 总数 + 排序。
      Row({ space: 8 }) {
        Text('评论')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary(Theme.isDark()))
        if (this.panelState.total !== null) {
          Text(`${this.panelState.total} 条`)
            .fontSize(13)
            .fontColor(Theme.textSecondary(Theme.isDark()))
        }
        Blank()
        if (this.panelState.status === CommentListStatus.SUCCESS) {
          this.sortChips()
        }
      }
      .width('100%')
      .padding({ bottom: 10 })

      if (this.panelState.likeError !== null) {
        this.likeErrorBanner()
      }
      if (this.panelState.error !== null && this.panelState.status === CommentListStatus.SUCCESS) {
        this.loadErrorBanner()
      }

      if (this.panelState.status === CommentListStatus.LOADING) {
        this.centeredNotice($r('sys.symbol.ellipsis_bubble'), '评论加载中…', '', true)
      } else if (this.panelState.status === CommentListStatus.ERROR) {
        this.centeredNotice($r('sys.symbol.wifi_badge_exclamationmark'),
          this.panelState.error !== null ? commentErrorText(this.panelState.error) : '评论加载失败', '重试', false)
      } else if (this.panelState.comments.length === 0) {
        this.centeredNotice($r('sys.symbol.text_bubble_left_2'), '暂无评论', '', false)
      } else {
        List({ space: 0 }) {
          ForEach(this.panelState.comments, (comment: SongComment) => {
            ListItem() {
              CommentItemRow({
                commentJson: SongCommentCodec.toJson(comment),
                isLiking: this.panelState.likingIds.has(comment.id),
                replyThreadJson: this.replyThreadJson(comment.id),
                canInteract: this.canInteract(),
                onToggleLike: (commentId: string) => {
                  if (this.controller !== null) {
                    this.controller.toggleLike(commentId);
                  }
                },
                onToggleReplies: () => {
                  if (this.controller !== null) {
                    this.controller.toggleReplies(comment.id);
                  }
                },
                onLoadMoreReplies: () => {
                  if (this.controller !== null) {
                    void this.controller.loadReplies(comment.id);
                  }
                },
                onReply: (target: CommentReplyTarget) => {
                  if (this.controller !== null) {
                    this.controller.replyTo(target);
                  }
                }
              })
            }
          }, (comment: SongComment) => comment.id)

          ListItem() {
            Column({ space: 8 }) {
              if (this.panelState.isLoadingMore) {
                LoadingProgress().width(22).height(22).color(Theme.textSecondary(Theme.isDark()))
              } else if (this.panelState.loadMoreError !== null) {
                Text(`${commentErrorText(this.panelState.loadMoreError)} 点击重试`)
                  .fontSize(12)
                  .fontColor(Theme.textSecondary(Theme.isDark()))
                  .onClick(() => {
                    if (this.controller !== null) {
                      this.controller.loadMore();
                    }
                  })
              } else if (!this.panelState.hasMore) {
                Text('已经到底了')
                  .fontSize(12)
                  .fontColor(Theme.textSecondary(Theme.isDark()))
              }
            }
            .width('100%')
            .padding({ top: 12, bottom: 12 })
            .justifyContent(FlexAlign.Center)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
        .onReachEnd(() => {
          if (this.controller !== null) {
            this.controller.loadMore();
          }
        })
      }

      if (this.canInteract()) {
        CommentComposer({
          draft: this.panelState.draft,
          replyTargetJson: this.panelState.replyTarget !== null
            ? CommentReplyTargetJson.from(this.panelState.replyTarget) : '',
          isSending: this.panelState.isSending,
          sendErrorText: this.panelState.sendError !== null ? commentErrorText(this.panelState.sendError) : '',
          limit: commentLengthLimit(this.platform()),
          onDraft: (text: string) => {
            if (this.controller !== null) {
              this.controller.updateDraft(text);
            }
          },
          onCancelReply: () => {
            if (this.controller !== null) {
              this.controller.replyTo(null);
            }
          },
          onSend: () => {
            if (this.controller !== null) {
              this.controller.sendComment();
            }
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 12 })
  }
}

/**
 * 单条评论行：头像 + 昵称/等级 + 富文本正文 + 引用 + 配图 + 点赞/回复操作
 * + 展开的楼中楼。上游 CommentItem/CommentReplies 的合并移植。
 */
@Component
struct CommentItemRow {
  @Prop commentJson: string = '';
  @Prop isLiking: boolean = false;
  @Prop replyThreadJson: string = '';
  @Prop canInteract: boolean = false;
  onToggleLike: (commentId: string) => void = (_commentId: string) => {};
  onToggleReplies: () => void = () => {};
  onLoadMoreReplies: () => void = () => {};
  onReply: (target: CommentReplyTarget) => void = (_target: CommentReplyTarget) => {};

  private comment(): SongComment {
    return SongCommentCodec.fromJson(this.commentJson);
  }

  private thread(): CommentReplyPanelState | null {
    return CommentReplyPanelStateCodec.fromJson(this.replyThreadJson);
  }

  private repliesLabel(): string {
    const thread = this.thread();
    const count = this.comment().replyCount ?? (thread !== null ? thread.comments.length : 0);
    if (thread === null) {
      return `展开 ${count} 条回复`;
    }
    return thread.expanded ? '收起回复' : `展开 ${count} 条回复`;
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        if (this.comment().avatarUrl !== null) {
          Image(this.comment().avatarUrl as string)
            .width(34)
            .height(34)
            .borderRadius(17)
            .autoResize(true)
        } else {
          Column() {
            Text(this.comment().username.length > 0 ? this.comment().username.substring(0, 1) : '?')
              .fontSize(15)
              .fontColor('#FFFFFF')
          }
          .width(34)
          .height(34)
          .borderRadius(17)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(Theme.primary(false))
        }
        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Text(this.comment().username)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary(Theme.isDark()))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (this.comment().userLevel !== null) {
              Text(`Lv${this.comment().userLevel as number}`)
                .fontSize(10)
                .fontColor(Theme.primary(false))
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                .borderRadius(6)
                .backgroundColor(Theme.withAlpha(Theme.primary(false), 0.1))
            }
          }
          .width('100%')
          Text(formatCommentTime(this.comment().createTime, Date.now()))
            .fontSize(11)
            .fontColor(Theme.textSecondary(Theme.isDark()))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // 点赞：数量 + 心形；网易只读（canInteract=false）保留展示不响应。
        Column({ space: 2 }) {
          if (this.isLiking) {
            LoadingProgress().width(16).height(16).color(Theme.textSecondary(Theme.isDark()))
          } else {
            SymbolGlyph(this.comment().isLiked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
              .fontSize(18)
              .fontColor([this.comment().isLiked ? Theme.danger(false) : Theme.textSecondary(Theme.isDark())])
          }
          Text(`${this.comment().likeCount}`)
            .fontSize(10)
            .fontColor(Theme.textSecondary(Theme.isDark()))
        }
        .onClick(() => {
          if (this.canInteract) {
            this.onToggleLike(this.comment().id);
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      CommentRichText({ commentJson: this.commentJson })

      ForEach(this.comment().quotedComments, (quote: CommentQuote, index: number) => {
        Text(`@${quote.username}：${quote.content ?? '评论已删除'}`)
          .fontSize(12)
          .fontColor(Theme.textSecondary(Theme.isDark()))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding(8)
          .borderRadius(8)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .width('100%')
      }, (quote: CommentQuote, index: number) => `${index}`)

      if (this.comment().images.length > 0) {
        Row({ space: 6 }) {
          ForEach(this.comment().images.slice(0, 3), (image: CommentImage, index: number) => {
            Image(image.url)
              .height(72)
              .aspectRatio(image.aspectRatio())
              .borderRadius(8)
              .autoResize(true)
          }, (image: CommentImage, index: number) => `${index}:${image.url}`)
        }
        .width('100%')
      }

      if ((this.comment().replyCount ?? 0) > 0 || this.thread() !== null) {
        Text(this.repliesLabel())
          .fontSize(12)
          .fontColor(Theme.primary(false))
          .padding({ top: 2, bottom: 2 })
          .onClick(() => this.onToggleReplies())
      }

      if (this.thread() !== null && (this.thread() as CommentReplyPanelState).expanded) {
        CommentRepliesSection({
          threadJson: this.replyThreadJson,
          rootId: this.comment().id,
          canInteract: this.canInteract,
          onToggleLike: this.onToggleLike,
          onReply: this.onReply,
          onLoadMore: () => this.onLoadMoreReplies()
        })
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }
}

/** 富文本正文：按 emotes 占位符切段，文本段 Span、表情段 ImageSpan 内联。 */
@Component
struct CommentRichText {
  @Prop commentJson: string = '';

  private comment(): SongComment {
    return SongCommentCodec.fromJson(this.commentJson);
  }

  build() {
    Text() {
      ForEach(buildCommentSegments(this.comment().content, this.comment().emotes),
        (segment: CommentTextSegment) => {
          if (segment.emoteUrl !== null) {
            ImageSpan(segment.emoteUrl as string)
              .width(18)
              .height(18)
              .verticalAlign(ImageSpanAlignment.CENTER)
          } else {
            Span(segment.text)
              .fontSize(14)
              .fontColor(Theme.textPrimary(Theme.isDark()))
          }
        }, (segment: CommentTextSegment, index: number) => `${index}:${segment.text.length}`)
    }
    .width('100%')
    .textAlign(TextAlign.Start)
    .copyOption(CopyOptions.InApp)
  }
}

/** 楼中楼区：已加载回复 + 引用提示 + 分页加载（点赞与回复复用宿主回调链）。 */
@Component
struct CommentRepliesSection {
  @Prop threadJson: string = '';
  @Prop rootId: string = '';
  @Prop canInteract: boolean = false;
  onToggleLike: (commentId: string) => void = (_commentId: string) => {};
  onReply: (target: CommentReplyTarget) => void = (_target: CommentReplyTarget) => {};
  onLoadMore: () => void = () => {};

  private thread(): CommentReplyPanelState {
    return CommentReplyPanelStateCodec.fromJson(this.threadJson) ?? new CommentReplyPanelState();
  }

  build() {
    Column({ space: 6 }) {
      ForEach(this.thread().comments, (reply: SongComment) => {
        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Text(reply.username)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textSecondary(Theme.isDark()))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (this.canInteract) {
              Row({ space: 3 }) {
                SymbolGlyph(reply.isLiked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                  .fontSize(13)
                  .fontColor([reply.isLiked ? Theme.danger(false) : Theme.textSecondary(Theme.isDark())])
                if (reply.likeCount > 0) {
                  Text(`${reply.likeCount}`)
                    .fontSize(10)
                    .fontColor(Theme.textSecondary(Theme.isDark()))
                }
              }
              .onClick(() => {
                // 楼中楼与一级共用点赞入口（id 空间一致）。
                this.onToggleLike(reply.id);
              })
            }
          }
          .width('100%')
          Text(reply.content)
            .fontSize(13)
            .fontColor(Theme.textPrimary(Theme.isDark()))
            .width('100%')
          Row({ space: 8 }) {
            Text(formatCommentTime(reply.createTime, Date.now()))
              .fontSize(10)
              .fontColor(Theme.textSecondary(Theme.isDark()))
            if (this.canInteract) {
              Text('回复')
                .fontSize(10)
                .fontColor(Theme.primary(false))
                .onClick(() => {
                  this.onReply(new CommentReplyTarget(reply.id, this.rootId, reply.username));
                })
            }
          }
          .width('100%')
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })
      }, (reply: SongComment) => reply.id)

      if (this.thread().loading) {
        Row({ space: 6 }) {
          LoadingProgress().width(14).height(14).color(Theme.textSecondary(Theme.isDark()))
          Text('回复加载中…')
            .fontSize(11)
            .fontColor(Theme.textSecondary(Theme.isDark()))
        }
      } else if (this.thread().error !== null) {
        Text(`${commentErrorText(this.thread().error as CommentError)} 点击重试`)
          .fontSize(11)
          .fontColor(Theme.textSecondary(Theme.isDark()))
          .onClick(() => {
            this.onLoadMore();
          })
      } else if (this.thread().hasMore) {
        Text('加载更多回复')
          .fontSize(11)
          .fontColor(Theme.primary(false))
          .onClick(() => {
            this.onLoadMore();
          })
      }
    }
    .width('100%')
    .padding(10)
    .borderRadius(10)
    .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
  }
}

/** 底部输入区：回复目标提示 + 输入框 + 发送（仅可互动平台显示）。 */
@Component
struct CommentComposer {
  @Prop draft: string = '';
  @Prop replyTargetJson: string = '';
  @Prop isSending: boolean = false;
  @Prop sendErrorText: string = '';
  @Prop limit: number = 1000;
  onDraft: (text: string) => void = (_text: string) => {};
  onCancelReply: () => void = () => {};
  onSend: () => void = () => {};

  private replyUsername(): string {
    return CommentReplyTargetJson.usernameOf(this.replyTargetJson);
  }

  build() {
    Column({ space: 6 }) {
      if (this.replyUsername().length > 0) {
        Row({ space: 6 }) {
          Text(`回复 @${this.replyUsername()}`)
            .fontSize(12)
            .fontColor(Theme.primary(false))
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
            .fontSize(14)
            .fontColor([Theme.textSecondary(Theme.isDark())])
            .onClick(() => this.onCancelReply())
        }
        .width('100%')
      }
      if (this.sendErrorText.length > 0) {
        Text(this.sendErrorText)
          .fontSize(11)
          .fontColor(Theme.danger(false))
          .width('100%')
      }
      Row({ space: 8 }) {
        TextInput({ text: this.draft, placeholder: '说点什么…' })
          .fontSize(14)
          .height(38)
          .backgroundColor(Theme.surfaceVariant(Theme.isDark()))
          .borderRadius(19)
          .padding({ left: 14, right: 14 })
          .maxLength(this.limit)
          .layoutWeight(1)
          .onChange((text: string) => this.onDraft(text))
        Button(this.isSending ? '发送中' : '发送')
          .fontSize(13)
          .height(34)
          .padding({ left: 14, right: 14 })
          .backgroundColor(Theme.primary(false))
          .enabled(!this.isSending && this.draft.trim().length > 0)
          .onClick(() => this.onSend())
      }
      .width('100%')
    }
    .width('100%')
    .padding({ top: 8 })
    .border({ width: { top: 0.5 }, color: Theme.divider(Theme.isDark()) })
  }
}
