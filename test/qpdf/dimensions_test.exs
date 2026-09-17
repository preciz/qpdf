defmodule Qpdf.DimensionsTest do
  use ExUnit.Case, async: true

  alias Qpdf.Dimensions

  describe "parse/2" do
    test "parses MediaBox from Parent and handles CropBox" do
      json_data = %{
        "pages" => [
          %{"pageposfrom1" => 1, "object" => "1 0 R"}
        ],
        "objects" => %{
          "1 0 R" => %{
            "/Parent" => "2 0 R",
            "/CropBox" => [10.0, 10.0, 600.0, 780.0]
          },
          "2 0 R" => %{
            "/MediaBox" => [0.0, 0.0, 612.0, 792.0],
            "/Rotate" => 180
          }
        }
      }

      assert {:ok, dim} = Dimensions.parse(json_data, 1)
      assert dim.page == 1
      assert dim.width == 612.0
      assert dim.height == 792.0
      assert dim.rotation == 180
      assert dim.orientation == :portrait
      assert dim.paper_size == "Letter"
      assert dim.box.media == [0.0, 0.0, 612.0, 792.0]
      assert dim.box.crop == [10.0, 10.0, 600.0, 780.0]
    end

    test "handles missing parent and default fallback" do
      json_data = %{
        "pages" => [
          %{"pageposfrom1" => 1, "object" => "1 0 R"}
        ],
        "objects" => %{
          "1 0 R" => %{}
        }
      }

      assert {:ok, dim} = Dimensions.parse(json_data, 1)
      assert dim.box.media == [0.0, 0.0, 612.0, 792.0]
      assert dim.box.crop == [0.0, 0.0, 612.0, 792.0]
      assert dim.rotation == 0
    end

    test "returns error on invalid json map" do
      assert {:error, :invalid_json} = Dimensions.parse(%{}, :all)
      assert {:error, :invalid_json} = Dimensions.parse("invalid", :all)
    end
  end
end
