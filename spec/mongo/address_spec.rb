require 'spec_helper'

describe Mongo::Address do

  describe '#==' do

    context 'when the other host and port are the same' do

      let(:address) do
        described_class.new('127.0.0.1:27017')
      end

      let(:other) do
        described_class.new('127.0.0.1:27017')
      end

      it 'returns true' do
        expect(address).to eq(other)
      end
    end

    context 'when the other port is different' do

      let(:address) do
        described_class.new('127.0.0.1:27017')
      end

      let(:other) do
        described_class.new('127.0.0.1:27018')
      end

      it 'returns false' do
        expect(address).to_not eq(other)
      end
    end

    context 'when the other host is different' do

      let(:address) do
        described_class.new('127.0.0.1:27017')
      end

      let(:other) do
        described_class.new('127.0.0.2:27017')
      end

      it 'returns false' do
        expect(address).to_not eq(other)
      end
    end

    context 'when the other object is not an address' do

      let(:address) do
        described_class.new('127.0.0.1:27017')
      end

      it 'returns false' do
        expect(address).to_not eq('test')
      end
    end

    context 'when the addresses are identical unix sockets' do

      before do
        allow(::Socket).to receive(:getaddrinfo).twice.
          and_return([[nil,nil,nil,nil,::Socket::PF_UNIX]])
      end

      let(:address) do
        described_class.new('/path/to/socket.sock')
      end

      let(:other) do
        described_class.new('/path/to/socket.sock')
      end

      it 'returns true' do
        expect(address).to eq(other)
      end
    end
  end

  describe '#hash' do

    let(:address) do
      described_class.new('127.0.0.1:27017')
    end

    it 'hashes on the host and port' do
      expect(address.hash).to eq([ '127.0.0.1', 27017 ].hash)
    end
  end

  describe '#initialize' do

    context 'when providing an ipv4 host' do

      context 'when a port is provided' do

        let(:address) do
          described_class.new('127.0.0.1:27017')
        end

        it 'sets the port' do
          expect(address.port).to eq(27017)
        end

        it 'sets the host' do
          expect(address.host).to eq('127.0.0.1')
        end
      end

      context 'when no port is provided' do

        let(:address) do
          described_class.new('127.0.0.1')
        end

        it 'sets the port to 27017' do
          expect(address.port).to eq(27017)
        end

        it 'sets the host' do
          expect(address.host).to eq('127.0.0.1')
        end
      end
    end

    context 'when providing an ipv6 host' do

      before do
        allow(::Socket).to receive(:getaddrinfo).once.
          and_return([[nil,nil,nil,nil,::Socket::AF_INET6]])
      end

      context 'when a port is provided' do

        let(:address) do
          described_class.new('[::1]:27017')
        end

        it 'sets the port' do
          expect(address.port).to eq(27017)
        end

        it 'sets the host' do
          expect(address.host).to eq('::1')
        end
      end

      context 'when no port is provided' do

        let(:address) do
          described_class.new('[::1]')
        end

        it 'sets the port to 27017' do
          expect(address.port).to eq(27017)
        end

        it 'sets the host' do
          expect(address.host).to eq('::1')
        end
      end
    end

    context 'when providing a DNS entry' do

      context 'when a port is provided' do

        let(:address) do
          described_class.new('localhost:27017')
        end

        it 'sets the port' do
          expect(address.port).to eq(27017)
        end

        it 'sets the host' do
          expect(address.host).to eq('localhost')
        end
      end

      context 'when a port is not provided' do

        let(:address) do
          described_class.new('localhost')
        end

        it 'sets the port to 27017' do
          expect(address.port).to eq(27017)
        end

        it 'sets the host' do
          expect(address.host).to eq('localhost')
        end
      end
    end

    context 'when providing a socket path' do

      before do
        allow(::Socket).to receive(:getaddrinfo).once.
          and_return([[nil,nil,nil,nil,::Socket::PF_UNIX]])
      end

      let(:address) do
        described_class.new('/path/to/socket.sock')
      end

      it 'sets the port to nil' do
        expect(address.port).to be_nil
      end

      it 'sets the host' do
        expect(address.host).to eq('/path/to/socket.sock')
      end
    end
  end
end
