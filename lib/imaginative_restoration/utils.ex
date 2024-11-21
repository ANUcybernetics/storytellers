defmodule ImaginativeRestoration.Utils do
  @moduledoc false

  alias ImaginativeRestoration.Sketches.Sketch

  require Ash.Query

  def to_image!(%Vix.Vips.Image{} = image), do: image

  def to_image!("http" <> _ = url) do
    url
    |> Req.get!()
    |> Map.get(:body)
    |> Image.open!()
  end

  def to_image!("data:image/" <> _ = dataurl) do
    dataurl
    |> String.split(",", parts: 2)
    |> List.last()
    |> Base.decode64!()
    |> Image.open!()
  end

  def to_dataurl!(%Vix.Vips.Image{} = image) do
    image
    |> Image.write!(:memory, suffix: ".webp", effort: 10)
    |> Base.encode64()
    |> then(&("data:image/webp;base64," <> &1))
  end

  def to_dataurl!("http" <> _ = url) do
    url
    |> to_image!()
    |> to_dataurl!()
  end

  def to_dataurl!("data:image/webp" <> _ = dataurl), do: dataurl

  # convert other dataurls to webp
  def to_dataurl!("data:image/" <> _ = dataurl) do
    dataurl
    |> to_image!()
    |> to_dataurl!()
  end

  def crop!("data:image/" <> _ = dataurl, x, y, w, h) do
    dataurl
    |> to_image!()
    |> crop!(x, y, w, h)
  end

  def crop!(%Vix.Vips.Image{} = image, x, y, w, h) do
    Image.crop!(image, x, y, w, h)
  end

  def thumbnail!("data:image/" <> _ = dataurl, length \\ 300) do
    dataurl
    |> to_image!()
    |> Image.thumbnail!(length)
    |> to_dataurl!()
  end

  def upload_to_s3!(%Vix.Vips.Image{} = image, filename) do
    # Convert image to binary
    image_binary = Image.write!(image, :memory, suffix: ".webp")

    # Upload to S3
    response =
      Req.new()
      |> ReqS3.attach()
      |> Req.put!(
        url: "s3://imaginative-restoration-sketches/#{filename}",
        body: image_binary
      )

    case response do
      %{status: status} when status in 200..299 ->
        {:ok, "https://fly.storage.tigris.dev/imaginative-restoration-sketches/#{filename}"}

      _ ->
        {:error, "Failed to upload image"}
    end
  end

  def recent_sketches(count) do
    Sketch
    |> Ash.Query.for_read(:read)
    |> Ash.Query.filter(not is_nil(processed))
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(count)
    |> Ash.read!()
  end

  def changed_recently? do
    num_minutes = 5
    num_sketches = 5

    sketches =
      Sketch
      |> Ash.Query.filter(inserted_at > ago(^num_minutes, :minute))
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!()

    images = Enum.map(sketches, &to_image!(&1.raw))

    case images do
      # if there's fewer than n images, then we count it as "has changed recently"
      images when length(images) < num_sketches ->
        true

      # otherwise look at the average hash difference between the latest and previous images
      [latest | previous] ->
        diffs =
          Enum.map(previous, fn img ->
            {:ok, d} = Image.hamming_distance(latest, img)
            d
          end)

        mean = Enum.sum(diffs) / length(diffs)

        # the docs say "In general, a hamming distance of less than 10 indicates that the images are very similar."
        mean >= 10
    end
  end
end
