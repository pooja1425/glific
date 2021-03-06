defmodule Glific.Fixtures do
  @moduledoc """
  A module for defining fixtures that can be used in tests.
  """
  alias Faker.{
    DateTime,
    Person,
    Phone
  }

  alias Glific.{
    Contacts,
    Flows,
    Flows.WebhookLog,
    Groups,
    Messages,
    Messages.MessageMedia,
    Partners,
    Partners.Organization,
    Repo,
    Settings,
    Tags,
    Templates,
    Templates.SessionTemplate,
    Users
  }

  @doc """
  temp function for test to get org id. use sparingly
  """
  @spec get_org_id :: integer
  def get_org_id do
    organization = Organization |> Ecto.Query.first() |> Repo.one(skip_organization_id: true)
    organization.id
  end

  @doc false
  @spec contact_fixture(map()) :: Contacts.Contact.t()
  def contact_fixture(attrs \\ %{}) do
    valid_attrs = %{
      name: Person.name(),
      optin_time: DateTime.backward(1),
      last_message_at: DateTime.backward(0),
      phone: Phone.EnUs.phone(),
      status: :valid,
      bsp_status: :session_and_hsm,
      organization_id: get_org_id(),
      language_id: 1
    }

    {:ok, contact} =
      attrs
      |> Enum.into(valid_attrs)
      |> Contacts.create_contact()

    contact
  end

  @doc false
  @spec message_fixture(map()) :: Messages.Message.t()
  def message_fixture(attrs \\ %{}) do
    sender = contact_fixture(attrs)
    receiver = contact_fixture(attrs)

    valid_attrs = %{
      body: Faker.Lorem.sentence(),
      flow: :inbound,
      type: :text,
      bsp_message_id: Faker.String.base64(10),
      bsp_status: :enqueued,
      sender_id: sender.id,
      receiver_id: receiver.id,
      contact_id: receiver.id,
      organization_id: get_org_id()
    }

    {:ok, message} =
      attrs
      |> Enum.into(valid_attrs)
      |> Messages.create_message()

    message
  end

  @doc false
  @spec language_fixture(map()) :: Settings.Language.t()
  def language_fixture(attrs \\ %{}) do
    valid_attrs = %{
      label: Faker.Lorem.word(),
      label_locale: Faker.Lorem.word(),
      locale: Faker.Lorem.word(),
      is_active: true
    }

    {:ok, language} =
      attrs
      |> Enum.into(valid_attrs)
      |> Settings.language_upsert()

    language
  end

  @doc false
  @spec organization_fixture(map()) :: Organization.t()
  def organization_fixture(attrs \\ %{}) do
    contact =
      if Map.get(attrs, :contact_id),
        do: Contacts.get_contact!(attrs.contact_id),
        else: contact_fixture()

    valid_attrs = %{
      name: "Fixture Organization",
      shortcode: "fixture_org_shortcode",
      email: "replace@idk.org",
      last_communication_at: DateTime.backward(0),
      # lets just hope its there :)
      bsp_id: 1,
      # lets just hope its there :)
      default_language_id: 1,
      contact_id: contact.id,
      active_language_ids: [1],
      out_of_office: %{
        enabled: true,
        start_time: elem(Time.new(9, 0, 0), 1),
        end_time: elem(Time.new(20, 0, 0), 1),
        enabled_days: [
          %{enabled: true, id: 1},
          %{enabled: true, id: 2},
          %{enabled: true, id: 3},
          %{enabled: true, id: 4},
          %{enabled: true, id: 5},
          %{enabled: false, id: 6},
          %{enabled: false, id: 7}
        ]
      }
    }

    {:ok, organization} =
      attrs
      |> Enum.into(valid_attrs)
      |> Partners.create_organization()

    contact = Map.put(contact, :organization_id, organization.id)

    attrs = %{
      organization_id: organization.id,
      contact_id: contact.id
    }

    _user = user_fixture(attrs)

    Application.put_env(
      :glific,
      String.to_atom("provider_key_#{organization.id}"),
      "This is a fake key"
    )

    Partners.create_credential(%{
      organization_id: organization.id,
      shortcode: "gupshup",
      keys: %{
        url: "test_url",
        api_end_point: "test_api_end_point",
        handler: "Glific.Providers.Gupshup.Message",
        worker: "Glific.Providers.Gupshup.Worker",
        bsp_limit: 60
      },
      secrets: %{
        api_key: "Please enter your key here",
        app_name: "Please enter your App Name here"
      },
      is_active: true
    })

    # ensure we get the triggered values in this refresh
    organization = Partners.get_organization!(organization.id)

    # lets store the organization in the cache
    Partners.fill_cache(organization)

    organization
  end

  @doc false
  @spec tag_fixture(map()) :: Tags.Tag.t()
  def tag_fixture(attrs) do
    valid_attrs = %{
      label: "some label",
      shortcode: "somelabel",
      description: "some fixed description",
      locale: "en_US",
      is_active: true,
      is_reserved: true
    }

    attrs = Map.merge(valid_attrs, attrs)
    language = language_fixture()

    {:ok, tag} =
      attrs
      |> Map.put_new(:language_id, language.id)
      |> Tags.create_tag()

    tag
  end

  @doc false
  @spec message_tag_fixture(map()) :: Tags.MessageTag.t()
  def message_tag_fixture(attrs) do
    valid_attrs = %{
      message_id: message_fixture(attrs).id,
      tag_id: tag_fixture(attrs).id
    }

    {:ok, message_tag} =
      attrs
      |> Enum.into(valid_attrs)
      |> Tags.create_message_tag()

    message_tag
  end

  @doc false
  @spec contact_tag_fixture(map()) :: Tags.ContactTag.t()
  def contact_tag_fixture(attrs \\ %{}) do
    contact = contact_fixture(attrs)

    valid_attrs = %{
      contact_id: contact.id,
      tag_id: tag_fixture(attrs).id,
      organization_id: contact.organization_id
    }

    {:ok, contact_tag} =
      attrs
      |> Enum.into(valid_attrs)
      |> Tags.create_contact_tag()

    contact_tag
  end

  @doc false
  @spec session_template_fixture(map()) :: SessionTemplate.t()
  def session_template_fixture(attrs \\ %{}) do
    language = language_fixture()

    valid_attrs = %{
      label: "Default Template Label",
      shortcode: "default_template",
      body: "Default Template",
      type: :text,
      language_id: language.id,
      uuid: Ecto.UUID.generate(),
      organization_id: get_org_id()
    }

    {:ok, session_template} =
      attrs
      |> Enum.into(valid_attrs)
      |> Templates.create_session_template()

    valid_attrs_2 = %{
      label: "Another Template Label",
      shortcode: "another template",
      body: "Another Template",
      type: :text,
      language_id: language.id,
      parent_id: session_template.id,
      uuid: Ecto.UUID.generate(),
      organization_id: get_org_id()
    }

    {:ok, _session_template} =
      valid_attrs_2
      |> Templates.create_session_template()

    session_template
  end

  @doc false
  @spec group_fixture(map()) :: Groups.Group.t()
  def group_fixture(attrs \\ %{}) do
    valid_attrs = %{
      label: "Poetry group",
      description: "default description",
      organization_id: get_org_id()
    }

    {:ok, group} =
      attrs
      |> Enum.into(valid_attrs)
      |> Groups.create_group()

    %{
      label: "Default Group",
      is_restricted: false,
      organization_id: get_org_id()
    }
    |> Groups.create_group()

    %{
      label: "Restricted Group",
      is_restricted: true,
      organization_id: get_org_id()
    }
    |> Groups.create_group()

    group
  end

  @doc false
  @spec contact_group_fixture(map()) :: Groups.ContactGroup.t()
  def contact_group_fixture(attrs) do
    valid_attrs = %{
      contact_id: contact_fixture(attrs).id,
      group_id: group_fixture(attrs).id
    }

    {:ok, contact_group} =
      attrs
      |> Enum.into(valid_attrs)
      |> Groups.create_contact_group()

    contact_group
  end

  @doc false
  @spec group_contacts_fixture(map()) :: [Groups.ContactGroup.t(), ...]
  def group_contacts_fixture(attrs) do
    attrs = %{filter: attrs}

    group_fixture(attrs)

    [_glific_admin, c1, c2 | _] = Contacts.list_contacts(attrs)
    [g1, g2 | _] = Groups.list_groups(attrs)

    {:ok, cg1} =
      Groups.create_contact_group(%{
        contact_id: c1.id,
        group_id: g1.id,
        organization_id: attrs.filter.organization_id
      })

    {:ok, cg2} =
      Groups.create_contact_group(%{
        contact_id: c2.id,
        group_id: g1.id,
        organization_id: attrs.filter.organization_id
      })

    {:ok, cg3} =
      Groups.create_contact_group(%{
        contact_id: c1.id,
        group_id: g2.id,
        organization_id: attrs.filter.organization_id
      })

    [cg1, cg2, cg3]
  end

  @doc false
  @spec contact_tags_fixture(map()) :: [Tags.ContactTag.t(), ...]
  def contact_tags_fixture(attrs) do
    tag_fixture(attrs)

    attrs = %{filter: attrs}

    [c1, c2 | _] = Contacts.list_contacts(attrs)
    [t1, t2 | _] = Tags.list_tags(attrs)

    {:ok, ct1} =
      Tags.create_contact_tag(%{
        contact_id: c1.id,
        tag_id: t1.id,
        organization_id: c1.organization_id
      })

    {:ok, ct2} =
      Tags.create_contact_tag(%{
        contact_id: c2.id,
        tag_id: t1.id,
        organization_id: c1.organization_id
      })

    {:ok, ct3} =
      Tags.create_contact_tag(%{
        contact_id: c1.id,
        tag_id: t2.id,
        organization_id: c1.organization_id
      })

    [ct1, ct2, ct3]
  end

  @doc false
  @spec template_tag_fixture(map()) :: Tags.TemplateTag.t()
  def template_tag_fixture(attrs \\ %{}) do
    tag = tag_fixture(attrs)
    template = session_template_fixture(attrs)

    valid_attrs = %{
      template_id: template.id,
      tag_id: tag.id
    }

    {:ok, template_tag} =
      attrs
      |> Enum.into(valid_attrs)
      |> Tags.create_template_tag()

    template_tag
  end

  @doc false
  @spec flow_fixture(map()) :: Flows.Flow.t()
  def flow_fixture(attrs \\ %{}) do
    valid_attrs = %{
      name: "Test Flow",
      keywords: ["test_keyword"],
      flow_type: :message,
      version_number: "13.1.0",
      organization_id: get_org_id()
    }

    {:ok, flow} =
      attrs
      |> Enum.into(valid_attrs)
      |> Flows.create_flow()

    flow
  end

  @doc false
  @spec user_fixture(map()) :: Users.User.t()
  def user_fixture(attrs \\ %{}) do
    phone = Phone.EnUs.phone()

    valid_attrs = %{
      name: "some name",
      contact_id: contact_fixture(%{phone: phone}).id,
      phone: phone,
      password: "secret1234",
      password_confirmation: "secret1234",
      roles: ["admin"],
      # This should be static for all the user fixtures
      organization_id: get_org_id()
    }

    {:ok, user} =
      attrs
      |> Enum.into(valid_attrs)
      |> Users.create_user()

    user
  end

  @doc false
  @spec otp_hsm_fixture() :: SessionTemplate.t()
  def otp_hsm_fixture do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "status" => "success",
              "template" => %{
                "elementName" => "common_otp",
                "id" => "16e84186-97fa-454e-ac3b-8c9b94e53b4b",
                "languageCode" => "en_US",
                "status" => "APPROVED"
              }
            })
        }
    end)

    session_template_fixture(%{
      body: "Your OTP for {{1}} is {{2}}. This is valid for {{3}}.",
      shortcode: "common_otp",
      is_hsm: true,
      category: "ALERT_UPDATE",
      example: "Your OTP for [adding Anil as a payee] is [1234]. This is valid for [15 minutes].",
      language_id: organization_fixture().default_language_id
    })
  end

  @doc false
  @spec message_media_fixture(map()) :: MessageMedia.t()
  def message_media_fixture(attrs) do
    {:ok, message_media} =
      %{
        url: Faker.Avatar.image_url(),
        source_url: Faker.Avatar.image_url(),
        thumbnail: Faker.Avatar.image_url(),
        caption: Faker.String.base64(10),
        provider_media_id: Faker.String.base64(10),
        organization_id: attrs.organization_id
      }
      |> Messages.create_message_media()

    message_media
  end

  @doc false
  @spec group_messages_fixture(map()) :: nil
  def group_messages_fixture(attrs) do
    [cg1, _cg2, cg3] = group_contacts_fixture(attrs)

    {:ok, group_1} =
      Repo.fetch_by(Groups.Group, %{id: cg1.group_id, organization_id: attrs.organization_id})

    {:ok, group_2} =
      Repo.fetch_by(Groups.Group, %{id: cg3.group_id, organization_id: attrs.organization_id})

    valid_attrs = %{
      body: "group message",
      flow: :outbound,
      type: :text,
      organization_id: attrs.organization_id
    }

    Messages.create_and_send_message_to_group(valid_attrs, group_1)
    Messages.create_and_send_message_to_group(valid_attrs, group_2)
    nil
  end

  @doc false
  @spec webhook_log_fixture(map()) :: WebhookLog.t()
  def webhook_log_fixture(attrs) do
    valid_attrs = %{
      url: "some url",
      method: "GET",
      request_headers: %{
        "Accept" => "application/json",
        "X-Glific-Signature" => "random signature"
      },
      request_json: %{},
      response_json: %{},
      status_code: 200,
      status: "Success"
    }

    contact = contact_fixture(attrs)
    flow = flow_fixture(Map.merge(attrs, %{keywords: [], name: Person.name()}))

    valid_attrs =
      valid_attrs
      |> Map.merge(attrs)
      |> Map.put(:contact_id, contact.id)
      |> Map.put(:flow_id, flow.id)
      |> Map.put(:organization_id, flow.organization_id)

    {:ok, webhook_log} = WebhookLog.create_webhook_log(valid_attrs)

    webhook_log
  end
end
