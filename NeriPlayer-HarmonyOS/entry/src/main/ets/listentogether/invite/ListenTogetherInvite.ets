/**
 * Port of listentogether/invite/ListenTogetherInvite.kt.
 *
 * `signature` is the dedupe key the UI uses to avoid re-handling the same
 * invite; the field order and the `|` separator must stay as upstream so a
 * signature persisted by either client keeps the same meaning.
 */

export class ListenTogetherInvite {
  readonly roomId: string;
  readonly inviterNickname: string | null;
  readonly baseUrl: string | null;
  readonly joinSecret: string | null;
  readonly hasInvalidBaseUrl: boolean;

  constructor(
    roomId: string,
    inviterNickname: string | null = null,
    baseUrl: string | null = null,
    joinSecret: string | null = null,
    hasInvalidBaseUrl: boolean = false
  ) {
    this.roomId = roomId;
    this.inviterNickname = inviterNickname;
    this.baseUrl = baseUrl;
    this.joinSecret = joinSecret;
    this.hasInvalidBaseUrl = hasInvalidBaseUrl;
  }

  get signature(): string {
    const parts: string[] = [
      this.roomId,
      this.inviterNickname === null ? '' : this.inviterNickname,
      this.baseUrl === null ? '' : this.baseUrl,
      this.joinSecret === null ? '' : this.joinSecret,
      this.hasInvalidBaseUrl ? 'true' : 'false'
    ];
    return parts.join('|');
  }
}
