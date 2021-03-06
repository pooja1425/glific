defmodule Glific.Communications.Message do
  @moduledoc """
  The Message Communication Context, which encapsulates and manages tags and the related join tables.
  """
  import Ecto.Query
  require Logger

  alias Glific.{
    Communications,
    Contacts,
    Messages,
    Messages.Message,
    Partners,
    Repo,
    Taggers,
    Tags
  }

  @doc false
  defmacro __using__(_opts \\ []) do
    quote do
    end
  end

  @type_to_token %{
    text: :send_text,
    image: :send_image,
    audio: :send_audio,
    video: :send_video,
    document: :send_document,
    sticker: :send_sticker
  }

  @doc """
  Send message to receiver using define provider.
  """
  @spec send_message(Message.t(), map()) :: {:ok, Message.t()} | {:error, String.t()}
  def send_message(message, attrs \\ %{}) do
    message = Repo.preload(message, [:receiver, :sender, :media])

    Logger.info(
      "Sending message: type: '#{message.type}', contact_id: '#{message.receiver.id}', message_id: '#{
        message.id
      }'"
    )

    if Contacts.can_send_message_to?(message.receiver, message.is_hsm) do
      {:ok, _} =
        apply(
          Communications.provider_handler(message.organization_id),
          @type_to_token[message.type],
          [message, attrs]
        )

      publish_message(message)
    else
      log_error(message)
    end
  rescue
    # An exception is thrown if there is no provider handler and/or sending the message
    # via the provider fails
    _ ->
      log_error(message)
  end

  @spec log_error(Message.t()) :: {:error, String.t()}
  defp log_error(message) do
    Logger.error("Could not send message: message_id: '#{message.id}'")
    {:ok, _} = Messages.update_message(message, %{status: :contact_opt_out, bsp_status: nil})
    {:error, "Cannot send the message to the contact."}
  end

  @spec publish_message(Message.t()) :: {:ok, Message.t()}
  defp publish_message(message) do
    {
      :ok,
      if message.publish? do
        Communications.publish_data(message, :sent_message, message.organization_id)
      else
        message
      end
    }
  end

  @doc """
  Callback when message send succsully
  """
  @spec handle_success_response(Tesla.Env.t(), Message.t()) :: {:ok, Message.t()}
  def handle_success_response(response, message) do
    body = response.body |> Jason.decode!()

    {:ok, message} =
      message
      |> Poison.encode!()
      |> Poison.decode!(as: %Message{})
      |> Messages.update_message(%{
        bsp_message_id: body["messageId"],
        bsp_status: :enqueued,
        status: :sent,
        flow: :outbound,
        sent_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    publish_message_status(message)

    Tags.remove_tag_from_all_message(
      message.contact_id,
      ["notreplied", "unread"],
      message.organization_id,
      message.publish?
    )

    Taggers.TaggerHelper.tag_outbound_message(message)
    {:ok, message}
  end

  @spec build_error(any()) :: map()
  defp build_error(body) do
    cond do
      is_binary(body) -> %{message: body}
      is_map(body) -> body
      true -> %{message: inspect(body)}
    end
  end

  @spec fetch_and_publish_message_status(String.t()) :: any()
  defp fetch_and_publish_message_status(bsp_message_id) do
    with {:ok, message} <- Repo.fetch_by(Message, %{bsp_message_id: bsp_message_id}) do
      publish_message_status(message)
    end
  end

  @spec publish_message_status(Message.t()) :: any()
  defp publish_message_status(message) do
    if is_nil(message.group_id),
      do:
        Communications.publish_data(
          message,
          :update_message_status,
          message.organization_id
        )
  end

  @doc """
  Callback in case of any error while sending the message
  """
  @spec handle_error_response(Tesla.Env.t(), Message.t()) :: {:error, String.t()}
  def handle_error_response(response, message) do
    {:ok, message} =
      message
      |> Poison.encode!()
      |> Poison.decode!(as: %Message{})
      |> Messages.update_message(%{
        bsp_status: :error,
        status: :sent,
        flow: :outbound,
        errors: build_error(response.body)
      })

    publish_message_status(message)

    {:error, response.body}
  end

  @doc """
  Callback to update the provider status for a message
  """
  @spec update_bsp_status(String.t(), atom(), map()) :: any()
  def update_bsp_status(bsp_message_id, :error, errors) do
    # we are making an additional query to db to fetch message for sending message status subscription
    from(m in Message, where: m.bsp_message_id == ^bsp_message_id)
    |> Repo.update_all(set: [bsp_status: :error, errors: errors, updated_at: DateTime.utc_now()])

    fetch_and_publish_message_status(bsp_message_id)
  end

  def update_bsp_status(bsp_message_id, bsp_status, _params) do
    # we are making an additional query to db to fetch message for sending message status subscription
    from(m in Message, where: m.bsp_message_id == ^bsp_message_id)
    |> Repo.update_all(set: [bsp_status: bsp_status, updated_at: DateTime.utc_now()])

    fetch_and_publish_message_status(bsp_message_id)
  end

  @doc """
  Callback when we receive a message from whats app
  """
  @spec receive_message(map(), atom()) :: {:ok} | {:error, String.t()}
  def receive_message(%{organization_id: organization_id} = message_params, type \\ :text) do
    if Contacts.is_contact_blocked?(message_params.sender.phone, organization_id),
      do: {:ok},
      else: do_receive_message(message_params, type)
  end

  @spec do_receive_message(map(), atom()) :: {:ok} | {:error, String.t()}
  defp do_receive_message(%{organization_id: organization_id} = message_params, type) do
    Logger.info(
      "Received message: type: '#{type}', phone: '#{message_params.sender.phone}', id: '#{
        message_params.bsp_message_id
      }'"
    )

    {:ok, contact} =
      message_params.sender
      |> Map.put(:organization_id, organization_id)
      |> Contacts.maybe_create_contact()

    {:ok, contact} = Contacts.set_session_status(contact, :session)

    message_params =
      message_params
      |> Map.merge(%{
        type: type,
        sender_id: contact.id,
        receiver_id: Partners.organization_contact_id(organization_id),
        flow: :inbound,
        bsp_status: :delivered,
        status: :received,
        organization_id: contact.organization_id
      })

    cond do
      type == :text -> receive_text(message_params)
      type == :location -> receive_location(message_params)
      true -> receive_media(message_params)
    end
  end

  # handler for receiving the text message
  @spec receive_text(map()) :: :ok
  defp receive_text(message_params) do
    message_params
    |> Messages.create_message()
    |> Taggers.TaggerHelper.tag_inbound_message()
    |> Communications.publish_data(:received_message, message_params.organization_id)
    |> process_message()
  end

  # handler for receiving the media (image|video|audio|document|sticker)  message
  @spec receive_media(map()) :: {:ok}
  defp receive_media(message_params) do
    {:ok, message_media} = Messages.create_message_media(message_params)

    message_params
    |> Map.put(:media_id, message_media.id)
    |> Messages.create_message()
    |> Communications.publish_data(:received_message, message_params.organization_id)
    |> process_message()

    {:ok}
  end

  # handler for receiving the location message
  @spec receive_location(map()) :: :ok
  defp receive_location(message_params) do
    {:ok, message} = Messages.create_message(message_params)

    message_params
    |> Map.put(:contact_id, message_params.sender_id)
    |> Map.put(:message_id, message.id)
    |> Contacts.create_location()

    message
    |> Communications.publish_data(:received_message, message.organization_id)
    |> process_message()

    :ok
  end

  # lets have a default timeout of 3 seconds for each call
  @timeout 3000

  @spec process_message(Message.t()) :: :ok
  defp process_message(message) do
    # lets transfer the organization id and current user to the poolboy worker
    process_state = {
      Repo.get_organization_id(),
      Repo.get_current_user()
    }

    self = self()

    # We dont want to block the input pipeline, and we are unsure how long the consumer worker
    # will take. So we run it as a separate task
    # We will also set a short timeout for both the genserver and the poolboy transaction
    # this will be moot soon after we move webhooks to be handled asynchronously
    Task.async(fn ->
      :poolboy.transaction(
        Glific.Application.message_poolname(),
        fn pid ->
          try do
            GenServer.call(pid, {message, process_state, self}, @timeout)
          catch
            e, r ->
              error = "poolboy transaction caught error: #{inspect(e)}, #{inspect(r)}"
              Logger.error(error)
              Appsignal.send_error(:error, error, __STACKTRACE__)
              :ok
          end
        end
      )
    end)

    :ok
  end
end
