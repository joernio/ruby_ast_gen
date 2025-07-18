require 'temple'
require 'erb'

class ErbToRubyTransformer
  def initialize
    @parser = Temple::ERB::Parser.new
    @in_control_block = false
    @output_tmp_var = "self.joern__buffer"
    @in_do_block = false
    @inner_buffer = "joern__inner_buffer"
    @current_counter = 0
    @current_lambda_vars = ""
    @output = []
    @static_buff = []
  end

  def transform(input)
    ast = @parser.call(input)
    @output << "#{@output_tmp_var} = \"\""
    visit(ast)
    flush_static_block

    if @in_control_block || @in_do_block
      raise ::StandardError, "Invalid ERB Syntax"
    end
    <<~RUBY
      #{@output.join("\n")}
    RUBY
  end

  private

  def visit(node)
    return "" unless node.is_a?(Array)
    case node.first
    when :multi
      node[1..-1].each do |child|
        visit(child)
      end
    when :static
      unless node[1].to_s != nil && node[1].to_s.strip.empty?
        @static_buff << "\"#{node[1].to_s.gsub('"', '\"').strip}\""
      end
    when :dynamic
      unless node[1].to_s != nil && node[1].to_s.strip.empty?
        @output << "\"#{node[1].to_s.gsub('"', '\"')}\""
      end
    when :escape
      flush_static_block
      escape_enabled = node[1]
      inner_node = node[2]
      code = inner_node[1].to_s

      if code.include?(" if ") || code.include?(" unless ")
        ast = extract_ast(code)
        if ast.is_a?(::Parser::AST::Node)
          case ast.type
          when :if
            if code.strip.start_with?("if") || code.strip.start_with?("unless")
              template_call = if escape_enabled
                                "joern__template_out_raw"
                              else
                                "joern__template_out_escape"
                              end

              if_cond = extract_code_snippet(ast.children[0].location, code)
              if_body = extract_code_snippet(ast.children[1].location, code) if ast.children[1]
              else_body = extract_code_snippet(ast.children[2].location, code) if ast.children[2]

              @output << "if #{if_cond}"
              @output << "#{template_call}(#{if_body})" if if_body
              @output << "else" if else_body
              @output << "#{@output_tmp_var} << #{template_call}(#{else_body})" if else_body
            else
              if code.include?(" if ")
                call, if_cond = code.split(" if ")
                @output << "if #{if_cond}"
              else
                call, if_cond = code.split(" unless ")
                @output << "unless #{if_cond}"
              end
              template_call = if escape_enabled
                                "joern__template_out_raw"
                              else
                                "joern__template_out_escape"
                              end
              @output << "#{@output_tmp_var} << #{template_call}(#{call})"
            end
            @output << "end"
          else
            template_call = if escape_enabled then
                              "joern__template_out_raw"
                            else
                              "joern__template_out_escape"
                            end
            @output << "#{@inner_buffer} << #{template_call}(#{code})"
          end
        end
      elsif is_do_block(code)
        # Do block with variable found, lower
        lower_do_block(code)
      elsif @in_do_block
        template_call = if escape_enabled then
                          "joern__template_out_raw"
                        else
                          "joern__template_out_escape"
                        end
        @output << "#{@inner_buffer} << #{template_call}(#{code})"
      else
        template_call = if escape_enabled then
                          "joern__template_out_raw"
                        else
                          "joern__template_out_escape"
                        end
        @output << "#{@output_tmp_var} << #{template_call}(#{code})"
      end
    when :code
      flush_static_block
      stripped_code = node[1].to_s.gsub("-", "").strip
      code = if node[1].strip.start_with?("-") then
               node[1].to_s.gsub("-", "")
             else
               node[1].to_s
             end
      unless stripped_code.empty?
        if is_control_struct_start(stripped_code)
          @in_control_block = true
          @output << stripped_code
        elsif stripped_code == "end"
          if @in_do_block
            @in_do_block = false
            @output << "#{@inner_buffer}"
            @output << "end"
            @output << "#{@output_tmp_var} << #{current_lambda}.call(#{@current_lambda_vars})"
          else
            @in_control_block = false
            @output << "end"
          end
        elsif is_do_block(code)
          lower_do_block(code)
        else
          @output << code
        end
      end
    when :newline
    else
      RubyAstGen::Logger::debug("Invalid node type: #{node}")
    end
  end

  def is_control_struct_start(line)
    line.start_with?('if', 'unless', 'elsif', 'else', /@?.+\.(each|each_with_index)\sdo/)
  end

  def lambda_incrementor()
    new_lambda = "rails_lambda_#{@current_counter}"
    @current_counter += 1
    new_lambda
  end

  def current_lambda()
    "rails_lambda_#{@current_counter - 1}"
  end

  def flush_static_block()
    unless @static_buff.empty?
      buffer_to_use = if @in_do_block then
                        @inner_buffer
                      else
                        @output_tmp_var
                      end
      @output << "#{buffer_to_use} << \"#{@static_buff.join('\n').gsub(/(?<!\\)"/, '')}\""
      @static_buff = [] # clear static buffer
    end
  end

  def lower_do_block(code)
    if (code_match = code.match(/do\s+(?:\|([^|]*)\|)?/) || code.end_with?('do'))
      if code.include?("=")
        @output << code
      elsif code.strip.end_with?("end")
        ast = extract_ast(code)
        if ast.is_a?(::Parser::AST::Node)
          case ast.type
          when :block
            call = extract_code_snippet(ast.children[0].location, code) if ast.children[0]
            args = extract_code_snippet(ast.children[1].location, code) if ast.children[1]
            body = extract_code_snippet(ast.children[2].location, code) if ast.children[2]
            @output << "#{@output_tmp_var} << #{call}"
            @output << "#{lambda_incrementor} = lambda do |#{args if args}|"
            @output << "#{@inner_buffer} = \"\""
            @output << "#{@inner_buffer} << #{body}"
            @output << "end"
          else
            code
          end
        end
      else
        @current_lambda_vars = code_match[1]
        before_do, _ = code.split(/\bdo\b/)
        unless before_do.nil?
          method_call = before_do.strip
          call_name, rest = method_call.split(' ', 2)
          if method_call.start_with?('[')
            method_call = method_call
          elsif rest != nil && !rest.start_with?('(') && !rest.end_with?(')')
            method_call = "#{call_name}(#{rest})"
          end
          @output << "#{@output_tmp_var} << #{method_call}"
        end
        @in_do_block = true
        @output << "#{lambda_incrementor} = lambda do |#{@current_lambda_vars}|"
        @output << "#{@inner_buffer} = \"\""
      end
    end
  end

  def is_do_block(code)
    code.match(/do\s*(?:\|([^|]*)\|)?/)
  end

  def extract_code_snippet(location, source_code)
    return nil unless location
    range = location.expression || location
    return nil unless range.is_a?(Parser::Source::Range)
    snippet = source_code[range.begin_pos...range.end_pos]
    snippet.strip
  end

  def extract_ast(code)
    parser_buffer = Parser::Source::Buffer.new("internal_tmp_#{Time.now.nsec}")
    parser_buffer.source = code
    ruby_parser = Parser::CurrentRuby.new
    ruby_parser.parse(parser_buffer)
  end
end




