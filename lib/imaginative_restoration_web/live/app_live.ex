defmodule ImaginativeRestorationWeb.AppLive do
  @moduledoc false
  use ImaginativeRestorationWeb, :live_view

  import ImaginativeRestorationWeb.AppComponents

  alias ImaginativeRestoration.AI.Utils
  alias ImaginativeRestoration.Sketches.Sketch
  alias Phoenix.Socket.Broadcast

  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative flex items-center justify-center size-full">
      <div class="w-full max-w-[calc(100vh*4/3)] aspect-[4/3]">
        <div class="relative w-full h-full">
          <canvas id="boid-canvas" phx-hook="SketchCanvas" class="w-full h-full object-contain">
          </canvas>
        </div>
        <div class="absolute top-8 left-8 flex gap-8 h-[200px] backdrop-blur-md">
          <.webcam_capture capture_interval={30_000} />
          <div :if={@sketch} class="relative">
            <img
              src={if pipeline_phase(@sketch) == :labelling, do: @sketch.raw, else: @sketch.cropped}
              class={[
                "h-full w-auto object-contain",
                pipeline_phase(@sketch) != :completed && "sketch-processing"
              ]}
            />
            <span
              :if={@sketch.label}
              class="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 text-4xl font-semibold px-2 py-1 text-white backdrop-blur-md rounded-sm"
            >
              <%= @sketch.label %>
            </span>
          </div>
          <img
            :if={@sketch && @sketch.processed}
            src={@sketch.processed}
            class="h-full w-auto object-contain"
          />
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      ImaginativeRestorationWeb.Endpoint.subscribe("sketch:updated")
    end

    {:ok, assign(socket, sketch: nil), layout: {ImaginativeRestorationWeb.Layouts, :canvas}}
  end

  @impl true
  def handle_event("webcam_frame", %{"frame" => dataurl}, socket) do
    # only run the AI pipeline if stuff has changed recently
    if Utils.changed_recently?() do
      # spawn the task which will communicate back to self() via :update_sketch messages
      Task.start(fn ->
        dataurl
        |> ImaginativeRestoration.Sketches.init!()
        |> ImaginativeRestoration.Sketches.crop_and_set_prompt!()
        |> ImaginativeRestoration.Sketches.process!()
      end)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(%Broadcast{topic: "sketch:updated", event: "process"} = message, socket) do
    sketch = message.payload.data

    {:noreply,
     socket
     |> assign(sketch: sketch)
     |> push_event("new_sketch", %{id: sketch.id, dataurl: sketch.processed})}
  end

  @impl true
  def handle_info(%Broadcast{topic: "sketch:updated"} = message, socket) do
    sketch = message.payload.data
    {:noreply, assign(socket, sketch: sketch)}
  end

  defp pipeline_phase(%Sketch{label: nil}), do: :labelling
  defp pipeline_phase(%Sketch{processed: nil}), do: :processing
  defp pipeline_phase(%Sketch{}), do: :completed
  defp pipeline_phase(nil), do: :waiting
end