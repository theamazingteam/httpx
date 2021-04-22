# frozen_string_literal: true

module Requests
  module Plugins
    module GRPC
      include GRPCHelpers

      def test_plugin_grpc_unary_plain_bytestreams
        no_marshal = proc { |x| x }

        server_port = run_request_response("a_reply", OK, marshal: no_marshal) do |call|
          assert call.remote_read == "a_request"
          assert call.metadata["k1"] == "v1"
          assert call.metadata["k2"] == "v2"
        end

        # stub = ::GRPC::ClientStub.new("localhost:#{server_port}",
        #                               :this_channel_is_insecure)
        grpc = HTTPX.plugin(:grpc)
        # build service
        stub = grpc.build_stub("http://localhost:#{server_port}")
        result = stub.execute("an_rpc_method", "a_request", metadata: { k1: "v1", k2: "v2" })
        # stub = ::GRPC::ClientStub.new("localhost:#{server_port}", :this_channel_is_insecure)
        # op = stub.request_response("an_rpc_method", "a_request", no_marshal, no_marshal,
        #   return_op: true, metadata: { k1: "v1", k2: "v2" })
        # op.start_call if run_start_call_first
        # result = op.execute

        assert result == "a_reply"
      end

      def test_plugin_grpc_unary_protobuf
        server_port = run_rpc(TestService)

        grpc = HTTPX.plugin(:grpc)

        # build service
        test_service_rpcs = grpc.rpc(:an_rpc, EchoMsg, EchoMsg, marshal_method: :marshal, unmarshal_method: :unmarshal)
        test_service_stub = test_service_rpcs.build_stub("http://localhost:#{server_port}", TestService)
        echo_response = test_service_stub.an_rpc(EchoMsg.new(msg: "ping"))

        assert echo_response.msg == "ping"
        # assert echo_response.trailing_metadata["status"] == "OK"
      end

      def test_plugin_grpc_client_stream_protobuf
        server_port = run_rpc(TestService)

        grpc = HTTPX.plugin(:grpc)

        # build service
        test_service_rpcs = grpc.rpc(:a_client_streaming_rpc, EchoMsg, EchoMsg, marshal_method: :marshal, unmarshal_method: :unmarshal)
        test_service_stub = test_service_rpcs.build_stub("http://localhost:#{server_port}", TestService)

        input = [EchoMsg.new(msg: "ping"), EchoMsg.new(msg: "ping")]
        response = test_service_stub.a_client_streaming_rpc(input)

        assert response.msg == "client stream pong"
        # assert echo_response.trailing_metadata["status"] == "OK"
      end

      def test_plugin_grpc_server_stream_protobuf
        server_port = run_rpc(TestService)

        grpc = HTTPX.plugin(:grpc)

        # build service
        test_service_rpcs = grpc.rpc(:a_server_streaming_rpc, EchoMsg, EchoMsg, marshal_method: :marshal, unmarshal_method: :unmarshal,
                                                                                stream: true)
        test_service_stub = test_service_rpcs.build_stub("http://localhost:#{server_port}", TestService)
        streaming_response = test_service_stub.a_server_streaming_rpc(EchoMsg.new(msg: "ping"))

        assert streaming_response.respond_to?(:each)
        # assert streaming_response.trailing_metadata.nil?

        echo_responses = streaming_response.each.to_a
        assert echo_responses.map(&:msg) == ["server stream pong", "server stream pong"]
        # assert echo_response.trailing_metadata["status"] == "OK"
      end

      def test_plugin_grpc_bidi_stream_protobuf
        server_port = run_rpc(TestService)

        grpc = HTTPX.plugin(:grpc)

        # build service
        test_service_rpcs = grpc.rpc(:a_bidi_rpc, EchoMsg, EchoMsg, marshal_method: :marshal, unmarshal_method: :unmarshal, stream: true)
        test_service_stub = test_service_rpcs.build_stub("http://localhost:#{server_port}", TestService)
        input = [EchoMsg.new(msg: "ping"), EchoMsg.new(msg: "ping")]
        streaming_response = test_service_stub.a_bidi_rpc(input)

        assert streaming_response.respond_to?(:each)
        # assert streaming_response.trailing_metadata.nil?

        echo_responses = streaming_response.each.to_a
        assert echo_responses.map(&:msg) == ["bidi pong", "bidi pong"]
        # assert echo_response.trailing_metadata["status"] == "OK"
      end
    end
  end
end
