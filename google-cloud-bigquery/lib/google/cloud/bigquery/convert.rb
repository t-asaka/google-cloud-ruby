# Copyright 2017 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


require "google/apis/bigquery_v2"
require "stringio"
require "base64"
require "time"
require "date"

module Google
  module Cloud
    module Bigquery
      # rubocop:disable all

      ##
      # @private
      #
      # Internal conversion of raw data values to/from Bigquery values
      #
      # | BigQuery    | Ruby           | Notes  |
      # |-------------|----------------|---|
      # | `BOOL`      | `true`/`false` | |
      # | `INT64`     | `Integer`      | |
      # | `FLOAT64`   | `Float`        | |
      # | `STRING`    | `STRING`       | |
      # | `DATETIME`  | `DateTime`  | `DATETIME` does not support time zone. |
      # | `DATE`      | `Date`         | |
      # | `TIMESTAMP` | `Time`         | |
      # | `TIME`      | `Google::Cloud::BigQuery::Time` | |
      # | `BYTES`     | `File`, `IO`, `StringIO`, or similar | |
      # | `ARRAY` | `Array` | Nested arrays, `nil` values are not supported. |
      # | `STRUCT`    | `Hash`        | Hash keys may be strings or symbols. |

      module Convert
        ##
        # @private
        def self.format_rows rows, fields
          Array(rows).map do |row|
            # convert TableRow to hash to handle nested TableCell values
            format_row row.to_h, fields
          end
        end

        ##
        # @private
        def self.format_row row, fields
          Hash[fields.zip(row[:f]).map { |f, v | [f.name, format_value(v, f)] }]
        end

        def self.format_value value, field
          if value.nil?
            nil
          elsif value.empty?
            nil
          elsif value[:v].nil?
            nil
          elsif Array === value[:v]
            value[:v].map { |v| format_value v, field }
          elsif Hash === value[:v]
            if value[:v].empty?
              nil
            else
              format_row value[:v], field.fields
            end
          elsif field.type == "STRING"
            String value[:v]
          elsif field.type == "INTEGER"
            Integer value[:v]
          elsif field.type == "FLOAT"
            Float value[:v]
          elsif field.type == "BOOLEAN"
            (value[:v] == "true" ? true : (value[:v] == "false" ? false : nil))
          elsif field.type == "BYTES"
            StringIO.new Base64.decode64 value[:v]
          elsif field.type == "TIMESTAMP"
            ::Time.at Float(value[:v])
          elsif field.type == "TIME"
            Bigquery::Time.new value[:v]
          elsif field.type == "DATETIME"
            ::Time.parse("#{value[:v]} UTC").to_datetime
          elsif field.type == "DATE"
            Date.parse value[:v]
          else
            value[:v]
          end
        end

        ##
        # @private
        def self.to_query_param value
          if TrueClass === value
            return Google::Apis::BigqueryV2::QueryParameter.new(
              parameter_type:  Google::Apis::BigqueryV2::QueryParameterType.new(
                type: "BOOL"),
              parameter_value: Google::Apis::BigqueryV2::QueryParameterValue.new(
                value: true)
            )
          elsif FalseClass === value
            return Google::Apis::BigqueryV2::QueryParameter.new(
              parameter_type:  Google::Apis::BigqueryV2::QueryParameterType.new(
                type: "BOOL"),
              parameter_value: Google::Apis::BigqueryV2::QueryParameterValue.new(
                value: false)
            )
          elsif Integer === value
            return Google::Apis::BigqueryV2::QueryParameter.new(
              parameter_type:  Google::Apis::BigqueryV2::QueryParameterType.new(
                type: "INT64"),
              parameter_value: Google::Apis::BigqueryV2::QueryParameterValue.new(
                value: value)
            )
          elsif Float === value
            return Google::Apis::BigqueryV2::QueryParameter.new(
              parameter_type:  Google::Apis::BigqueryV2::QueryParameterType.new(
                type: "FLOAT64"),
              parameter_value: Google::Apis::BigqueryV2::QueryParameterValue.new(
                value: value)
            )
          elsif String === value
            return Google::Apis::BigqueryV2::QueryParameter.new(
              parameter_type:  Google::Apis::BigqueryV2::QueryParameterType.new(
                type: "STRING"),
              parameter_value: Google::Apis::BigqueryV2::QueryParameterValue.new(
                value: value)
            )
          elsif DateTime === value
            return Google::Apis::BigqueryV2::QueryParameter.new(
              parameter_type:  Google::Apis::BigqueryV2::QueryParameterType.new(
                type: "DATETIME"),
              parameter_value: Google::Apis::BigqueryV2::QueryParameterValue.new(
                value: value.strftime("%Y-%m-%d %H:%M:%S.%6N"))
            )
          elsif Date === value
            return Google::Apis::BigqueryV2::QueryParameter.new(
              parameter_type:  Google::Apis::BigqueryV2::QueryParameterType.new(
                type: "DATE"),
              parameter_value: Google::Apis::BigqueryV2::QueryParameterValue.new(
                value: value.to_s)
            )
          elsif ::Time === value
            return Google::Apis::BigqueryV2::QueryParameter.new(
              parameter_type:  Google::Apis::BigqueryV2::QueryParameterType.new(
                type: "TIMESTAMP"),
              parameter_value: Google::Apis::BigqueryV2::QueryParameterValue.new(
                value: value.strftime("%Y-%m-%d %H:%M:%S.%6N%:z"))
            )
          elsif Bigquery::Time === value
            return Google::Apis::BigqueryV2::QueryParameter.new(
              parameter_type:  Google::Apis::BigqueryV2::QueryParameterType.new(
              type: "TIME"),
              parameter_value: Google::Apis::BigqueryV2::QueryParameterValue.new(
                value: value.value)
            )
          elsif value.respond_to?(:read) && value.respond_to?(:rewind)
            value.rewind
            return Google::Apis::BigqueryV2::QueryParameter.new(
              parameter_type:  Google::Apis::BigqueryV2::QueryParameterType.new(
                type: "BYTES"),
              parameter_value: Google::Apis::BigqueryV2::QueryParameterValue.new(
                value: Base64.strict_encode64(
                  value.read.force_encoding("ASCII-8BIT")))
            )
          elsif Array === value
            array_params = value.map { |param| Convert.to_query_param param }
            return Google::Apis::BigqueryV2::QueryParameter.new(
              parameter_type: Google::Apis::BigqueryV2::QueryParameterType.new(
                type: "ARRAY",
                array_type: array_params.first.parameter_type
              ),
              parameter_value: Google::Apis::BigqueryV2::QueryParameterValue.new(
                array_values: array_params.map(&:parameter_value)
              )
            )
          elsif Hash === value
            struct_pairs = value.map do |name, param|
              struct_param = Convert.to_query_param param
              [Google::Apis::BigqueryV2::QueryParameterType::StructType.new(
                name: String(name),
                type: struct_param.parameter_type
              ), struct_param.parameter_value]
            end
            struct_values = Hash[struct_pairs.map do |type, value|
              [type.name, value]
            end]

            return Google::Apis::BigqueryV2::QueryParameter.new(
              parameter_type: Google::Apis::BigqueryV2::QueryParameterType.new(
                type: "STRUCT",
                struct_types: struct_pairs.map(&:first)
              ),
              parameter_value: Google::Apis::BigqueryV2::QueryParameterValue.new(
                struct_values: struct_values
              )
            )
          else
            fail "A query parameter of type #{value.class} is not supported."
          end
        end

        ##
        # @private
        def self.to_json_rows rows
          rows.map do |row|
            Hash[row.map { |k, v| [k.to_s, to_json_value(v)] }]
          end
        end
        ##
        # @private
        def self.to_json_row row
          Hash[row.map { |k, v| [k.to_s, to_json_value(v)] }]
        end
        ##
        # @private
        def self.to_json_value value
          if DateTime === value
            value.strftime "%Y-%m-%d %H:%M:%S.%6N"
          elsif Date === value
            value.to_s
          elsif ::Time === value
            value.strftime "%Y-%m-%d %H:%M:%S.%6N%:z"
          elsif Bigquery::Time === value
            value.value
          elsif value.respond_to?(:read) && value.respond_to?(:rewind)
            value.rewind
            Base64.strict_encode64(value.read.force_encoding("ASCII-8BIT"))
          elsif Array === value
            value.map { |v| to_json_value v }
          elsif Hash === value
            Hash[value.map { |k, v| [k.to_s, to_json_value(v)] }]
          else
            value
          end
        end

        def self.resolve_legacy_sql legacy_sql, standard_sql
          return !standard_sql unless standard_sql.nil?
          return legacy_sql unless legacy_sql.nil?
          false
        end

        # rubocop:enable all
      end
    end
  end
end
