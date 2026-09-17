defmodule Qpdf.DimensionsPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Qpdf.Dimensions

  property "orientation matches post-rotation geometry for arbitrary dimensions" do
    check all(
            w <- float(min: 10.0, max: 5000.0),
            h <- float(min: 10.0, max: 5000.0),
            rot <- member_of([0, 90, 180, 270])
          ) do
      json = build_mock_page_json(w, h, rot)

      assert {:ok, [dim]} = Dimensions.parse(json, :all)
      assert {:ok, single} = Dimensions.parse(json, 1)
      assert dim == single

      {expected_w, expected_h} =
        if rot in [90, 270], do: {h, w}, else: {w, h}

      assert_in_delta dim.width, expected_w, 0.01
      assert_in_delta dim.height, expected_h, 0.01

      expected_orientation =
        cond do
          abs(expected_w - expected_h) < 1.0 -> :square
          expected_w > expected_h -> :landscape
          true -> :portrait
        end

      assert dim.orientation == expected_orientation
    end
  end

  property "detects standard paper sizes regardless of rotation" do
    check all(
            {name, w, h} <-
              member_of([
                {"A4", 595.28, 841.89},
                {"Letter", 612.0, 792.0},
                {"Legal", 612.0, 1008.0},
                {"A3", 842.0, 1191.0}
              ]),
            rot <- member_of([0, 90, 180, 270]),
            # Slight deviation within tolerance
            delta_w <- float(min: -1.0, max: 1.0),
            delta_h <- float(min: -1.0, max: 1.0)
          ) do
      json = build_mock_page_json(w + delta_w, h + delta_h, rot)
      assert {:ok, dim} = Dimensions.parse(json, 1)
      assert dim.paper_size == name
    end
  end

  property "page filtering matches range and list selection invariants" do
    check all(
            total_pages <- integer(1..20),
            start_page <- integer(1..total_pages),
            end_page <- integer(start_page..total_pages)
          ) do
      pages =
        Enum.map(1..total_pages, fn idx ->
          build_page_entry(idx, "obj_#{idx}")
        end)

      objects =
        Map.new(1..total_pages, fn idx ->
          {"obj_#{idx}", %{"/MediaBox" => [0, 0, 500, 700], "/Rotate" => 0}}
        end)

      json = %{"pages" => pages, "objects" => objects}

      # Test range selection
      range = start_page..end_page
      assert {:ok, range_dims} = Dimensions.parse(json, range)
      assert length(range_dims) == end_page - start_page + 1
      assert Enum.map(range_dims, & &1.page) == Enum.to_list(range)

      # Test single page selection
      assert {:ok, single_dim} = Dimensions.parse(json, start_page)
      assert single_dim.page == start_page
    end
  end

  defp build_mock_page_json(w, h, rot) do
    %{
      "pages" => [
        build_page_entry(1, "page_obj_1")
      ],
      "objects" => %{
        "page_obj_1" => %{
          "/MediaBox" => [0, 0, w, h],
          "/Rotate" => rot
        }
      }
    }
  end

  defp build_page_entry(num, obj_id) do
    %{
      "pageposfrom1" => num,
      "object" => obj_id
    }
  end
end
