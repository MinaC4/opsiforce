import { Show, createEffect, createSignal, on } from 'solid-js';
import { Spinner } from '~/components/ui/spinner';
import { appHttpsPortSuffix } from '~/lib/app-url';

export function ProjectDbTab(props: { environmentId: string }) {
  const [loading, setLoading] = createSignal(true);
  const url = () => `https://${props.environmentId}.${import.meta.env.VITE_DB_DOMAIN}${appHttpsPortSuffix()}/`;

  createEffect(
    on(
      () => props.environmentId,
      () => setLoading(true)
    )
  );

  return (
    <div class="flex-1 min-w-0 flex flex-col relative">
      <Show when={loading()}>
        <Spinner overlay label="Loading database viewer..." />
      </Show>
      <iframe
        src={url()}
        class="flex-1 w-full border-0"
        allow="clipboard-read; clipboard-write"
        onLoad={() => setLoading(false)}
      />
    </div>
  );
}
