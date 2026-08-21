/**
 * Invalidates asynchronous room operations after a leave, room switch or
 * lifecycle teardown. Promise cancellation is not available for the platform
 * HTTP APIs, so callers capture a generation and drop results that no longer
 * belong to the active session.
 */
export class ListenTogetherSessionOperationGate {
  private generation: number = 0;

  begin(): number {
    this.generation++;
    return this.generation;
  }

  current(): number {
    return this.generation;
  }

  isCurrent(generation: number): boolean {
    return generation === this.generation;
  }
}
