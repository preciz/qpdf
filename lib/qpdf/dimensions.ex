defmodule Qpdf.Dimensions do
  @moduledoc """
  Parses page geometry, bounding boxes, dimensions, orientation, and standard paper sizes
  from qpdf JSON structural metadata.
  """

  @paper_sizes [
    {"A0", 2384.0, 3370.0},
    {"A1", 1684.0, 2384.0},
    {"A2", 1191.0, 1684.0},
    {"A3", 842.0, 1191.0},
    {"A4", 595.28, 841.89},
    {"A5", 419.53, 595.28},
    {"A6", 297.64, 419.53},
    {"Letter", 612.0, 792.0},
    {"Legal", 612.0, 1008.0},
    {"Tabloid", 792.0, 1224.0},
    {"Executive", 522.0, 756.0}
  ]

  @type orientation :: :portrait | :landscape | :square
  @type page_dim :: %{
          page: pos_integer(),
          width: float(),
          height: float(),
          rotation: non_neg_integer(),
          orientation: orientation(),
          paper_size: String.t() | nil,
          box: %{
            media: [float()],
            crop: [float()]
          }
        }

  @doc """
  Parses page dimensions from decoded qpdf v1 JSON data.
  """
  @spec parse(map(), :all | integer() | Range.t() | list()) ::
          {:ok, page_dim() | [page_dim()]} | {:error, any()}
  def parse(%{"pages" => pages} = data, page_spec) when is_list(pages) do
    objects = Map.get(data, "objects", %{})

    all_dims =
      Enum.map(pages, fn page ->
        page_num = page["pageposfrom1"]
        page_obj_key = page["object"]
        obj_data = Map.get(objects, page_obj_key, %{})

        media_box = resolve_media_box(obj_data, objects)
        crop_box = resolve_crop_box(obj_data, media_box)
        rotation = resolve_rotation(obj_data, objects)

        {width, height} = calculate_page_dimensions(media_box, rotation)
        orientation = determine_orientation(width, height)
        paper_size = detect_paper_size(width, height)

        %{
          page: page_num,
          width: width,
          height: height,
          rotation: rotation,
          orientation: orientation,
          paper_size: paper_size,
          box: %{
            media: media_box,
            crop: crop_box
          }
        }
      end)

    filter_dimensions(all_dims, page_spec)
  end

  def parse(_other, _page_spec), do: {:error, :invalid_json}

  defp resolve_media_box(obj_data, objects) do
    case obj_data["/MediaBox"] do
      [x0, y0, x1, y1]
      when is_number(x0) and is_number(y0) and is_number(x1) and is_number(y1) ->
        [x0 * 1.0, y0 * 1.0, x1 * 1.0, y1 * 1.0]

      _ ->
        case obj_data["/Parent"] do
          parent_key when is_binary(parent_key) ->
            resolve_media_box(objects[parent_key] || %{}, objects)

          _ ->
            [0.0, 0.0, 612.0, 792.0]
        end
    end
  end

  defp resolve_crop_box(obj_data, fallback) do
    case obj_data["/CropBox"] do
      [x0, y0, x1, y1]
      when is_number(x0) and is_number(y0) and is_number(x1) and is_number(y1) ->
        [x0 * 1.0, y0 * 1.0, x1 * 1.0, y1 * 1.0]

      _ ->
        fallback
    end
  end

  defp resolve_rotation(obj_data, objects) do
    case obj_data["/Rotate"] do
      rot when is_integer(rot) ->
        rem(rem(rot, 360) + 360, 360)

      _ ->
        case obj_data["/Parent"] do
          parent_key when is_binary(parent_key) ->
            resolve_rotation(objects[parent_key] || %{}, objects)

          _ ->
            0
        end
    end
  end

  defp calculate_page_dimensions([x0, y0, x1, y1], rotation) do
    raw_w = abs(x1 - x0)
    raw_h = abs(y1 - y0)

    if rem(rotation, 180) == 90 do
      {Float.round(raw_h * 1.0, 2), Float.round(raw_w * 1.0, 2)}
    else
      {Float.round(raw_w * 1.0, 2), Float.round(raw_h * 1.0, 2)}
    end
  end

  defp determine_orientation(width, height) do
    cond do
      width > height -> :landscape
      width < height -> :portrait
      true -> :square
    end
  end

  defp detect_paper_size(width, height) do
    min_dim = min(width, height)
    max_dim = max(width, height)

    Enum.find_value(@paper_sizes, fn {name, pw, ph} ->
      target_min = min(pw, ph)
      target_max = max(pw, ph)

      if abs(min_dim - target_min) <= 3.0 and abs(max_dim - target_max) <= 3.0 do
        name
      else
        nil
      end
    end)
  end

  defp filter_dimensions(all_dims, :all), do: {:ok, all_dims}

  defp filter_dimensions(all_dims, page_num) when is_integer(page_num) do
    case Enum.find(all_dims, &(&1.page == page_num)) do
      nil -> {:error, :not_found}
      dim -> {:ok, dim}
    end
  end

  defp filter_dimensions(all_dims, %Range{} = range) do
    selected = Enum.filter(all_dims, &(&1.page in range))
    {:ok, selected}
  end

  defp filter_dimensions(all_dims, pages) when is_list(pages) do
    selected = Enum.filter(all_dims, &(&1.page in pages))
    {:ok, selected}
  end

  defp filter_dimensions(_all_dims, _other), do: {:error, :invalid_page_spec}
end
