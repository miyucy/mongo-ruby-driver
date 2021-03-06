require 'spec_helper'

describe 'change streams examples in Ruby', if: test_change_streams? do

  let!(:inventory) do
    client[:inventory]
  end

  let(:client) do
    authorized_client.with(max_pool_size: 5, wait_queue_timeout: 3)
  end

  before do
    inventory.drop
  end

  after do
    client.close
    inventory.drop
  end

  context 'example 1 - basic watching'do

    it 'returns a change after an insertion' do

      insert_thread = Thread.new do
        sleep 2
        inventory.insert_one(x: 1)
      end

      stream_thread = Thread.new do

        # Start Changestream Example 1

        cursor = inventory.watch.to_enum
        next_change = cursor.next

        # End Changestream Example 1
      end

      insert_thread.value
      change = stream_thread.value

      expect(change['_id']).not_to be_nil
      expect(change['_id']['_data']).not_to be_nil
      expect(change['operationType']).to eq('insert')
      expect(change['fullDocument']).not_to be_nil
      expect(change['fullDocument']['_id']).not_to be_nil
      expect(change['fullDocument']['x']).to eq(1)
      expect(change['ns']).not_to be_nil
      expect(change['ns']['db']).to eq(TEST_DB)
      expect(change['ns']['coll']).to eq(inventory.name)
      expect(change['documentKey']).not_to be_nil
      expect(change['documentKey']['_id']).to eq(change['fullDocument']['_id'])
    end
  end

  context 'example 2 - full document update lookup specified' do

    it 'returns a change and the delta after an insertion' do

      inventory.insert_one(_id: 1, x: 2)

      update_thread = Thread.new do
        sleep 2
        inventory.update_one({ _id: 1}, { '$set' => { x: 5 }})
      end

      stream_thread = Thread.new do

        # Start Changestream Example 2

        cursor = inventory.watch([], full_document: 'updateLookup').to_enum
        next_change = cursor.next

        # End Changestream Example 2
      end


      update_thread.value
      change = stream_thread.value

      expect(change['_id']).not_to be_nil
      expect(change['_id']['_data']).not_to be_nil
      expect(change['operationType']).to eq('update')
      expect(change['fullDocument']).not_to be_nil
      expect(change['fullDocument']['_id']).to eq(1)
      expect(change['fullDocument']['x']).to eq(5)
      expect(change['ns']).not_to be_nil
      expect(change['ns']['db']).to eq(TEST_DB)
      expect(change['ns']['coll']).to eq(inventory.name)
      expect(change['documentKey']).not_to be_nil
      expect(change['documentKey']['_id']).to eq(1)
      expect(change['updateDescription']).not_to be_nil
      expect(change['updateDescription']['updatedFields']).not_to be_nil
      expect(change['updateDescription']['updatedFields']['x']).to eq(5)
      expect(change['updateDescription']['removedFields']).to eq([])
    end
  end

  context 'example 3 - resuming from a previous change' do

    it 'returns the correct change when resuming' do

      stream = inventory.watch
      cursor = stream.to_enum
      inventory.insert_one(x: 1)
      next_change = cursor.next

      expect(next_change['_id']).not_to be_nil
      expect(next_change['_id']['_data']).not_to be_nil
      expect(next_change['operationType']).to eq('insert')
      expect(next_change['fullDocument']).not_to be_nil
      expect(next_change['fullDocument']['_id']).not_to be_nil
      expect(next_change['fullDocument']['x']).to eq(1)
      expect(next_change['ns']).not_to be_nil
      expect(next_change['ns']['db']).to eq(TEST_DB)
      expect(next_change['ns']['coll']).to eq(inventory.name)
      expect(next_change['documentKey']).not_to be_nil
      expect(next_change['documentKey']['_id']).to eq(next_change['fullDocument']['_id'])

      inventory.insert_one(x: 2)
      next_next_change = cursor.next
      stream.close

      expect(next_next_change['_id']).not_to be_nil
      expect(next_next_change['_id']['_data']).not_to be_nil
      expect(next_next_change['operationType']).to eq('insert')
      expect(next_next_change['fullDocument']).not_to be_nil
      expect(next_next_change['fullDocument']['_id']).not_to be_nil
      expect(next_next_change['fullDocument']['x']).to eq(2)
      expect(next_next_change['ns']).not_to be_nil
      expect(next_next_change['ns']['db']).to eq(TEST_DB)
      expect(next_next_change['ns']['coll']).to eq(inventory.name)
      expect(next_next_change['documentKey']).not_to be_nil
      expect(next_next_change['documentKey']['_id']).to eq(next_next_change['fullDocument']['_id'])

      # Start Changestream Example 3

      resume_token = next_change['_id']
      cursor = inventory.watch([], resume_after: resume_token).to_enum
      resumed_change = cursor.next

      # End Changestream Example 3

      expect(resumed_change.length).to eq(next_next_change.length)
      resumed_change.each { |key| expect(resumed_change[key]).to eq(next_next_change[key]) }
    end
  end
end
