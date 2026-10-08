/**
 * The documents beyond Home that the parsers' tests read: a library's Discover, browse
 * capabilities, a browse page and facets for each tab's pivot; a movie's title page, credits and
 * playback options; a show's workspace; an album, an artist and a book; search; the saved lists,
 * playlists and history; the guide. Called by scripts/fixtures.mjs with a signed-in `request`.
 */
import {libraryTabs} from '../../portico-server/packages/client-core/src/presentation/library-tabs.ts';
import {rokuDeclaredProfile} from '../../portico-server/packages/client-core/src/client-profile.ts';
import {capabilityProfileFromClient} from '../../portico-server/packages/client-core/src/playback-v1/capability-profile.ts';
import {guideWindow} from '../../portico-server/packages/client-core/src/channel-guide.ts';
import {randomUUID} from 'node:crypto';

const enc = encodeURIComponent;

export default async function more({keep, request, save, libraries, home}) {
  const firstOf = {};
  for (const library of libraries?.items ?? []) {
    const kind = library.kind;
    const base = `/v1/libraries/${enc(library.id)}`;
    await keep(`library-${kind}-discover.json`, `${base}/content?view=discover&limit=40`);
    for (const tab of libraryTabs(kind, {owner: true, unmatched: true})) {
      if (!tab.pivot || tab.fixedFilter) continue;
      const capabilities = await keep(`library-${kind}-capabilities-${tab.pivot}.json`, `${base}/browse-capabilities?pivot=${enc(tab.pivot)}`);
      const sort = tab.fixedSort ?? capabilities?.resolvedPivot?.defaultSort?.[0] ?? {field: 'title', direction: 'asc'};
      const name = tab.fixedSort ? `${tab.pivot}-${tab.id}` : tab.pivot;
      const page = await keep(`library-${kind}-browse-${name}.json`, `${base}/browse`, 'POST', {pivot: tab.pivot, sort: [sort], limit: 60, range: {start: 0}});
      if (page?.entries?.length && !firstOf[`${kind}:${tab.pivot}`]) firstOf[`${kind}:${tab.pivot}`] = {library, entry: page.entries[0]};
    }
    await keep(`library-${kind}-facets-genre.json`, `${base}/facets?field=genre&limit=100`);
  }
  const movie = firstOf['movie:movies'];
  if (movie) {
    await keep('item-movie-detail.json', `/v1/items/${enc(movie.entry.id)}/detail?related=all`);
    await keep('item-movie-credits.json', `/v1/items/${enc(movie.entry.id)}/credits?group=cast`);
    const detail = await keep('item-movie-detail.json', `/v1/items/${enc(movie.entry.id)}/detail?related=all`);
    const person = detail?.metadata?.credits?.find(c => c.personId)?.personId;
    if (person) {
      await keep('person.json', `/v1/people/${enc(person)}?limit=40&role=all`);
      await keep('person-cast.json', `/v1/people/${enc(person)}?limit=40&role=cast`);
    }
    await keep('item-movie-recommendations.json', `/v1/items/${enc(movie.entry.id)}/recommendations?limit=12`);
    await keep('container-album.json', '/v1/containers/album/' + enc(firstOf['music:albums']?.entry.id ?? 'none') + '/personal-state');
    await keep('item-movie-playback-options.json', `/v1/items/${enc(movie.entry.id)}/playback-options`);
  }
  const show = firstOf['tv:shows'];
  if (show) {
    const workspace = await keep('show-workspace.json', `/v1/libraries/${enc(show.library.id)}/show-workspace?showId=${enc(show.entry.id)}&limit=40&seasonLimit=128`);
    await keep('show-recommendations.json', `/v1/shows/${enc(show.entry.id)}/recommendations?limit=12`);
    await keep('container-show.json', `/v1/containers/show/${enc(show.entry.id)}/personal-state`);
    const season = workspace?.seasons?.[workspace.seasons.length - 1];
    if (season) await keep('show-workspace-season.json', `/v1/libraries/${enc(show.library.id)}/show-workspace?showId=${enc(show.entry.id)}&selectedSeasonId=${enc(season.id)}&limit=40&seasonLimit=128`);
    const episode = workspace?.episodes?.sections?.[0]?.entries?.[0];
    if (episode) {
      await keep('item-episode-detail.json', `/v1/items/${enc(episode.id)}/detail?related=all`);
      await keep('item-episode-playback-options.json', `/v1/items/${enc(episode.id)}/playback-options`);
    }
  }
  for (const [key, view] of [['music:albums', 'album'], ['music:artists', 'artist'], ['audiobook:books', 'book'], ['audiobook:authors', 'author'], ['movie:collections', 'collection']]) {
    const found = firstOf[key];
    if (found) await keep(`entity-${view}.json`, `/v1/libraries/${enc(found.library.id)}/content?view=${view}&entityId=${enc(found.entry.id)}&limit=40`);
  }
  const song = firstOf['music:songs'];
  if (song) await keep('item-song-playback-options.json', `/v1/items/${enc(song.entry.playback?.itemId ?? song.entry.id)}/playback-options`);
  const term = (home?.rows?.flatMap(r => r.entries)?.find(e => e.kind === 'movie')?.title ?? 'the').split(/\s+/)[0];
  await keep('search.json', `/v1/search?q=${enc(term)}&limit=40`);
  await keep('search-movies.json', `/v1/search?q=${enc(term)}&limit=40&group=movies`);
  await keep('search-the.json', '/v1/search?q=the&limit=40');
  await keep('saved-watchlist.json', '/v1/content?view=watchlist&limit=40');
  await keep('saved-favorites.json', '/v1/content?view=favorites&limit=40');
  await keep('saved-playlists.json', '/v1/content?view=playlists&limit=40');
  await keep('saved-history.json', '/v1/personal-history?limit=40');
  const collections = await keep('saved-collections.json', '/v1/saved-resources?limit=40&kind=collection');
  const views = await keep('saved-views.json', '/v1/saved-resources?limit=40&kind=view');
  if (collections?.resources?.[0]) await keep('saved-collection-content.json', `/v1/saved-resources/${enc(collections.resources[0].id)}/content?limit=40`);
  if (views?.resources?.[0]) await keep('saved-view-content.json', `/v1/saved-resources/${enc(views.resources[0].id)}/content?limit=40`);
  await keep('direct.json', '/v1/direct');
  await keep('me.json', '/v1/me');
  // Watch Together (social-playback.ts): a group is made, given a title and an invitation, and ended again.
  if (movie) {
    const group = await request('/v1/groups', 'POST', {protocolVersion: '1.0', name: 'Fixtures', displayName: 'Roku', hostAuthority: 'host-only'});
    console.log(`fixtures: group create answered ${group.status}${group.status >= 300 ? ' ' + JSON.stringify(group.data).slice(0, 200) : ''}`);
    if (group.status >= 200 && group.status < 300 && group.data?.group?.id) {
      save('group-snapshot.json', group.data);
      const id = group.data.group.id;
      await keep('group-list.json', '/v1/groups');
      await keep('group-invite.json', `/v1/groups/${enc(id)}/invites`, 'POST', {protocolVersion: '1.0', expiresInSeconds: 900, maxUses: 8});
      const added = await request(`/v1/groups/${enc(id)}/queue`, 'POST', {protocolVersion: '1.0', idempotencyKey: randomUUID(), expectedRevision: group.data.group.queueRevision, operation: 'append', itemIds: [movie.entry.id]});
      console.log(`fixtures: group queue add answered ${added.status}`);
      const queue = await keep('group-queue.json', `/v1/groups/${enc(id)}/queue`);
      const now = await request(`/v1/groups/${enc(id)}`, 'GET');
      const entry = (queue?.queue ?? queue)?.entries?.[0];
      if (entry && now.status === 200) {
        const loaded = await request(`/v1/groups/${enc(id)}/transport`, 'POST', {protocolVersion: '1.0', idempotencyKey: randomUUID(), expectedRevision: now.data.group.revision, command: 'load', entryId: entry.entryId});
        console.log(`fixtures: group load answered ${loaded.status}${loaded.status >= 300 ? ' ' + JSON.stringify(loaded.data).slice(0, 200) : ''}`);
        if (loaded.status >= 200 && loaded.status < 300) save('group-transport.json', loaded.data);
        await keep('group-snapshot-loaded.json', `/v1/groups/${enc(id)}`);
        const after = await request(`/v1/groups/${enc(id)}`, 'GET');
        const played = await request(`/v1/groups/${enc(id)}/transport`, 'POST', {protocolVersion: '1.0', idempotencyKey: randomUUID(), expectedRevision: after.data?.group?.revision, command: 'play'});
        console.log(`fixtures: group play answered ${played.status}${played.status >= 300 ? ' ' + JSON.stringify(played.data).slice(0, 200) : ''}`);
        if (played.status >= 200 && played.status < 300) { save('group-transport-play.json', played.data); await keep('group-snapshot-playing.json', `/v1/groups/${enc(id)}`); }
      }
      const last = await request(`/v1/groups/${enc(id)}`, 'GET');
      const ended = await request(`/v1/groups/${enc(id)}/end`, 'POST', {protocolVersion: '1.0', expectedRevision: last.data?.group?.revision});
      console.log(`fixtures: group end answered ${ended.status}`);
      await keep('group-snapshot-ended.json', `/v1/groups/${enc(id)}`);
    }
  }
  // A Library Channel to tune (the development server starts with none): made once from the
  // server's first applicable template, as the web's channel builder does. This changes the
  // development server; nothing is removed.
  const existing = await request('/v1/admin/library-channels', 'GET');
  if (existing.status === 200 && Array.isArray(existing.data?.channels) && existing.data.channels.length === 0) {
    const templates = await request('/v1/admin/library-channels/templates', 'GET');
    const template = (templates.data?.templates ?? []).find(t => t.applicable);
    if (template) {
      const made = await request('/v1/admin/library-channels', 'POST', {config: template.config, expectedRevision: 0, requestId: randomUUID()});
      console.log(`fixtures: library channel "${template.name}" create answered ${made.status}${made.status >= 300 ? ' ' + JSON.stringify(made.data).slice(0, 300) : ''}`);
    } else console.log(`fixtures: no applicable library channel template (templates answered ${templates.status})`);
  } else console.log(`fixtures: library channels answered ${existing.status} with ${existing.data?.channels?.length ?? '?'} channel(s)`);
  const now = await request('/v1/admin/library-channels', 'GET');
  for (const c of now.data?.channels ?? []) console.log(`fixtures: library channel ${JSON.stringify(Object.fromEntries(Object.entries(c).filter(([, v]) => typeof v !== 'object' || v === null)))} config keys ${Object.keys(c.config ?? {}).join(',')}`);
  // The guide, as the Apple app asks for it (channel-guide.ts `path`): one window of each kind.
  const window = guideWindow();
  for (const kind of ['live-source', 'library-channel']) {
    const q = new URLSearchParams({kind, start: window.start, end: window.end, timezone: 'UTC', search: '', sourceId: '', limit: '30', cursor: ''});
    const guide = await keep(`guide-${kind}.json`, '/v1/guide?' + q.toString());
    // Tuning (playback-v1/channel-control.ts): one session for the first channel that can be tuned, then stopped.
    const channel = guide?.guide?.channels?.find(c => c.tuneAvailable);
    if (channel) {
      const id = kind === 'live-source' ? `live:${channel.sourceId}:${channel.id}` : `library:${channel.id}`;
      const tuned = await request('/v1/playback/sessions', 'POST', {channelId: id, channelGeneration: channel.generation, state: 'playing'}, {'Idempotency-Key': randomUUID()});
      console.log(`fixtures: tuning ${kind} answered ${tuned.status}${tuned.status >= 300 ? ' ' + JSON.stringify(tuned.data).slice(0, 300) : ''}`);
      if (tuned.status >= 200 && tuned.status < 300) {
        save(`playback-channel-session-${kind}.json`, tuned.data);
        const session = tuned.data.session ?? tuned.data;
        if (session?.id) await request(`/v1/playback/sessions/${enc(session.id)}`, 'DELETE');
      }
    }
  }
  // Settings: the preference registry and values for a television, and the Dashboard's documents.
  await keep('preferences-television.json', '/v1/preferences?deviceClass=television');
  await keep('admin-sessions.json', '/v1/admin/sessions?limit=50');
  await keep('admin-alerts.json', '/v1/admin/console/alerts');
  await keep('admin-panel-health.json', '/v1/admin/console/panels/health');
  await keep('admin-panel-storage.json', '/v1/admin/console/panels/storage');
  await keep('admin-telemetry-1h.json', '/v1/admin/telemetry?window=1h');
  await keep('admin-jobs.json', '/v1/admin/console/jobs?cursor=');
  await keep('system.json', '/v1/system');
  await keep('profile-avatars.json', '/v1/direct/profiles/avatars');
  // The devices this account is signed in on, as this installation sees them (a made installation id: the list marks none as this device).
  await keep('devices.json', '/v1/devices?installationId=' + 'fixtures'.padEnd(40, '0'));
  for (const view of ['all', 'unread']) await keep(`notifications-inbox-${view}.json`, `/v1/notifications/inbox?audience=profile&state=${view}&limit=50`);
  await keep('notifications-inbox-admin.json', '/v1/notifications/inbox?audience=account-admin&state=all&limit=50');
  await keep('notifications-unread.json', '/v1/notifications/unread-count?audience=profile');

  // Playback v1: what this device publishes, then a session and a queue (stopped and deleted again).
  const profile = rokuDeclaredProfile({osVersion: '14.0', model: 'fixtures', uhd: true});
  await keep('playback-client-profile-receipt.json', '/v1/playback/client-profile', 'PUT', profile);
  await keep('playback-capabilities-receipt.json', '/v1/me/devices/current/capabilities', 'PUT', capabilityProfileFromClient(profile, {form: 'tv', network: {class: 'local'}}));
  const key = () => ({'Idempotency-Key': randomUUID()});
  if (movie) {
    const started = await request('/v1/playback/sessions', 'POST', {itemId: movie.entry.id, startFrom: 'beginning', state: 'paused', quality: {mode: 'original'}, network: 'local'}, key());
    if (started.status === 201 || started.status === 200) {
      save('playback-session.json', started.data);
      const session = started.data.session ?? started.data;
      const report = await request(`/v1/playback/sessions/${enc(session.id)}/timeline`, 'POST', {seq: 1, generation: session.presentation.generation, state: 'paused', positionMs: 0, rate: 1});
      console.log(`fixtures: timeline answered ${report.status}`);
      const limited = await request(`/v1/playback/sessions/${enc(session.id)}`, 'PATCH', {quality: {mode: 'limit', maxVideoBitrateKbps: 4000, maxHeight: 720}}, {'If-Match': session.revision, 'Content-Type': 'application/merge-patch+json'});
      if (limited.status === 200) save('playback-session-limited.json', limited.data); else console.log(`fixtures: session change answered ${limited.status}`);
      await request(`/v1/playback/sessions/${enc(session.id)}`, 'DELETE');
    } else console.log(`fixtures: session start answered ${started.status} ${JSON.stringify(started.data).slice(0, 200)}`);
  }
  const album = firstOf['music:albums'];
  if (album) {
    const made = await request('/v1/queues', 'POST', {owner: 'device', segments: [{source: {container: {kind: 'album', id: album.entry.id}}}], startPlayback: {state: 'paused'}}, key());
    if (made.status >= 200 && made.status < 300) {
      save('playback-queue.json', made.data);
      const queue = made.data.queue;
      const next = await request(`/v1/queues/${enc(queue.id)}:advance`, 'POST', {reason: 'next'}, {'If-Match': queue.revision, ...key()});
      if (next.status >= 200 && next.status < 300) save('playback-queue-advance.json', next.data); else console.log(`fixtures: queue advance answered ${next.status}`);
      const session = next.data?.session ?? made.data.session;
      // The lyrics of what that session plays (lyrics.ts): bound to the session and its generation.
      if (session?.itemId) await keep('lyrics.json', `/v1/items/${enc(session.itemId)}/lyrics?sessionId=${enc(session.id)}`);
      if (session) await request(`/v1/playback/sessions/${enc(session.id)}`, 'DELETE');
      await request(`/v1/queues/${enc(queue.id)}`, 'DELETE');
    } else console.log(`fixtures: queue create answered ${made.status} ${JSON.stringify(made.data).slice(0, 200)}`);
  }
}
