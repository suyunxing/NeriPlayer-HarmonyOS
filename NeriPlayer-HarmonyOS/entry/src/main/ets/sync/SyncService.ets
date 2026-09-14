// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/** App-facing entry points for manual GitHub and WebDAV synchronization. */

import { getSyncFileName, serializeSyncDataJson } from './SyncDataJsonCodec';
import { serializeSyncDataBinary } from './SyncDataProtoCodec';
import { SyncData } from './SyncModels';
import { SettingsRepository } from '../data/SettingsRepository';
import { SyncCoordinator, SyncCoordinatorOptions } from './SyncCoordinator';
import { GitHubSyncBackend, WebDavSyncBackend } from './SyncBackends';
import { SyncAppLocalStore } from './SyncAppLocalStore';
import { SyncReport } from './SyncReport';
import { GitHubConfigRepository } from './github/GitHubConfigRepository';
import { GitHubTransport } from './github/GitHubTransport';
import { OhosGhExecutor } from './github/OhosGhExecutor';
import { WebDavConfigRepository } from './webdav/WebDavConfigRepository';
import { OhosWebDavExecutor } from './webdav/OhosWebDavExecutor';
import { WebDavSyncClient, WebDavTransport } from './webdav/WebDavTransport';

/**
 * Upload serializer per the sync data-saver switch (backlog §1.3): JSON bytes
 * normally, GZIP(Protobuf) (~15% size) in data-saver mode — the exact format
 * Android SyncDataSerializer produces for the same setting.
 */
function uploadSerializer(useDataSaver: boolean): (data: SyncData) => Uint8Array {
  if (useDataSaver) {
    return (data: SyncData): Uint8Array => serializeSyncDataBinary(data);
  }
  return (data: SyncData): Uint8Array => serializeSyncDataJson(data);
}

export class SyncService {
  static async syncGitHub(): Promise<SyncReport> {
    const config = await GitHubConfigRepository.loadConfig();
    if (config === null) {
      return failure('请先配置 GitHub 仓库与令牌');
    }
    const local = new SyncAppLocalStore();
    const backend = new GitHubSyncBackend(
      new GitHubTransport(new OhosGhExecutor(), config.token),
      config.owner, config.repo, getSyncFileName(config.dataSaver), config.dataSaver);
    const options = new SyncCoordinatorOptions();
    options.serialize = uploadSerializer(config.dataSaver);
    options.lastSyncTime = await GitHubConfigRepository.getLastSyncTime();
    options.lastRemoteVersion = await GitHubConfigRepository.getLastRemoteSha();
    options.favoritesPlaylistId = local.favoritesPlaylistId();
    const report = await new SyncCoordinator(backend, local).run(options);
    if (report.success) {
      if (report.remoteVersion.length > 0) {
        await GitHubConfigRepository.saveLastRemoteSha(report.remoteVersion);
      }
      if (!report.localChangedDuringSync) {
        await GitHubConfigRepository.saveLastSyncTime(Date.now());
      }
    }
    return report;
  }

  static async syncWebDav(): Promise<SyncReport> {
    const config = await WebDavConfigRepository.loadConfig();
    if (config === null) {
      return failure('请先配置 WebDAV 服务器与凭据');
    }
    const local = new SyncAppLocalStore();
    const transport = new WebDavTransport(new OhosWebDavExecutor(), config.username, config.password);
    const backend = new WebDavSyncBackend(new WebDavSyncClient(transport), config.remoteFileUrl());
    const options = new SyncCoordinatorOptions();
    // Android treats data-saver as one global switch shared by GitHub/WebDAV;
    // the key was named per-transport on this side, so WebDAV reads it too.
    options.serialize = uploadSerializer(
      SettingsRepository.getBoolean(SettingsRepository.KEY_SYNC_DATA_SAVER, false));
    options.lastSyncTime = await WebDavConfigRepository.getLastSyncTime();
    options.lastRemoteVersion = await WebDavConfigRepository.getLastRemoteFingerprint();
    options.favoritesPlaylistId = local.favoritesPlaylistId();
    const report = await new SyncCoordinator(backend, local).run(options);
    if (report.success) {
      if (report.remoteVersion.length > 0) {
        await WebDavConfigRepository.saveLastRemoteFingerprint(report.remoteVersion);
      }
      if (!report.localChangedDuringSync) {
        await WebDavConfigRepository.saveLastSyncTime(Date.now());
      }
    }
    return report;
  }
}

function failure(message: string): SyncReport {
  const report = new SyncReport();
  report.success = false;
  report.message = message;
  return report;
}
