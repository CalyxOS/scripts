#!/usr/bin/env python3

import argparse
from collections import OrderedDict
from glob import glob
from itertools import product
import os.path
import sys
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape, quoteattr

from carrier_settings_pb2 import CarrierSettings, MultiCarrierSettings
from carrier_list_pb2 import CarrierList
from carrierId_pb2 import CarrierList as CarrierIdList


def indent(elem, level=0):
    """Based on https://effbot.org/zone/element-lib.htm#prettyprint"""
    i = "\n" + level * "    "
    if len(elem):
        if not elem.text or not elem.text.strip():
            elem.text = i + "    "
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
        for elem in elem:
            indent(elem, level + 1)
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
    else:
        if level and (not elem.tail or not elem.tail.strip()):
            elem.tail = i


def parse_args():
    parser = argparse.ArgumentParser(
        description="Convert the CarrierSettings protobuf files to XML format compatible with AOSP")
    parser.add_argument('-i', '--input', help='CarrierSettings folder',
                        required=True)
    parser.add_argument('-a', '--apns', help='apns-conf.xml Output folder',
                        required=False)
    parser.add_argument('-v', '--vendor', help='vendor.xml Output folder',
                        required=True)
    return parser.parse_args()


unwanted_configs = [
                    # Anything where the value is a package name
                    "carrier_app_wake_signal_config",
                    "carrier_settings_activity_component_name_string",
                    "carrier_setup_app_string",
                    "config_ims_package_override_string",
                    "enable_apps_string_array",
                    "gps.nfw_proxy_apps",
                    "smart_forwarding_config_component_name_string",
                    "wfc_emergency_address_carrier_app_string",
                    # Always allow editing APNs
                    "apn_expand_bool",
                    "allow_adding_apns_bool",
                    "read_only_apn_types_string_array",
                    "read_only_apn_fields_string_array",
                    # Ignore motorola specific configs
                    "carrier_moto_allow_calls_over_IMS_only_bool",
                    "moto_WEA3_overshoot_allowed",
                    "moto_additional_international_roaming_network_string_array",
                    "moto_allow_hold_in_gsm_call",
                    "moto_app_directed_sms_enabled",
                    "moto_append_filler_digits_to_iccid",
                    "moto_auto_answer",
                    "moto_auto_resume_holding_call",
                    "moto_auto_retry_enabled",
                    "moto_back_to_auto_network_selection_timer",
                    "moto_call_end_tone_and_call_end_toast",
                    "moto_carrier_airplane_mode_alert_bool",
                    "moto_carrier_chatbot_supported_bool",
                    "moto_carrier_fdn_numbers_string_array",
                    "moto_carrier_format_device_info",
                    "moto_carrier_hide_meid",
                    "moto_carrier_specific_rtt_req_bool",
                    "moto_carrier_specific_vice_req_bool",
                    "moto_carrier_specific_vt_req_bool",
                    "moto_carrier_specific_wfc_req_bool",
                    "moto_carrier_vonr_available_bool",
                    "moto_cdma_dbm_thresholds_int_array",
                    "moto_cdma_ecio_thresholds_int_array",
                    "moto_check_camped_csg_bool",
                    "moto_common_rtt_enabled_bool",
                    "moto_convert_plus_for_ims_call_bool",
                    "moto_custom_config_string",
                    "moto_customized_vvm_in_dialer_bool",
                    "moto_default_disable_initial_addressbook_scan_value_int",
                    "moto_delete_WEA_database",
                    "moto_display_noservice_dataiwlan_wificallingdisable",
                    "moto_dss_int",
                    "moto_ecbm_supported_bool",
                    "moto_enable_bcch_location_service",
                    "moto_enable_broadcast_phone_state_change",
                    "moto_enable_service_dialing_number",
                    "moto_enable_ussd_alert",
                    "moto_enriched_call_common_bool",
                    "moto_eri_banner",
                    "moto_evdo_dbm_thresholds_int_array",
                    "moto_evdo_ecio_thresholds_int_array",
                    "moto_evdo_snr_thresholds_int_array",
                    "moto_hide_delete_action_for_non_user_deletable_apn",
                    "moto_hide_smsc_edit_option_bool",
                    "moto_hide_wfc_mode_summary",
                    "moto_ims_call_priority_over_ussd_bool",
                    "moto_ims_callcomposer_default_usersetting_bool",
                    "moto_ims_useragent_format_str",
                    "moto_lppe_available_bool",
                    "moto_lte_rsrp_thresholds_per_band_string_array",
                    "moto_lte_show_one_bar_atleast_bool",
                    "moto_mms_gowith_ims_rat_bool",
                    "moto_mt_sms_filter_list",
                    "moto_multi_device_support",
                    "moto_need_delay_otasp",
                    "moto_operator_name_replace_string_array",
                    "moto_preferred_display_name",
                    "moto_prompt_call_ap_mode",
                    "moto_redial_alternate_service_call_over_cs",
                    "moto_rtt_while_roaming_supported_bool",
                    "moto_should_restore_anonymous_bool",
                    "moto_should_restore_unknown_participant_bool",
                    "moto_show_5g_warning_on_volte_off_bool",
                    "moto_show_brazil_settings",
                    "moto_show_customized_wfc_disclaimer_dialog",
                    "moto_show_customized_wfc_help_and_dialog_bool",
                    "moto_show_unsecured_wifi_network_dialog",
                    "moto_show_wfc_ussd_disclaimer_bool",
                    "moto_signal_strength_hysteresis_db_int",
                    "moto_signal_strength_max_level_int",
                    "moto_sprint_hd_codec",
                    "moto_ssrsrp_signal_strength_hysteresis_db_int",
                    "moto_ssrsrp_signal_threshold_offset_frequency_range_high_int",
                    "moto_ssrsrp_signal_threshold_offset_frequency_range_low_int",
                    "moto_ssrsrp_signal_threshold_offset_frequency_range_mid_int",
                    "moto_ssrsrp_signal_threshold_offset_frequency_range_mmwave_int",
                    "moto_sssinr_signal_strength_hysteresis_db_int",
                    "moto_stir_shaken_common_req_bool",
                    "moto_tdscdma_rscp_thresholds_int_array",
                    "moto_uce_messaging_feature_enabled_bool",
                    "moto_uce_video_feature_enabled_bool",
                    "moto_update_cb_with_password_over_ims",
                    "moto_update_ims_useragent_bool",
                    "moto_use_only_cdmadbm_for_cdma_signal_bar_bool",
                    "moto_use_only_evdodbm_for_evdo_signal_bar_bool",
                    "moto_use_restore_number_for_conference",
                    "moto_vt_common_req_bool",
                    "moto_vzw_voice_call_worldphone",
                    "moto_vzw_volte_specific_req",
                    "moto_vzw_wfc_enabled_bool",
                    "moto_vzw_world_phone",
                    "moto_wcdma_ecno_thresholds_int_array",
                    "moto_wcdma_rssi_thresholds_int_array",
                    "moto_wfc_spn"]


def extract_elements(carrier_config_element, config):
    if config.key in unwanted_configs:
        return
    value_type = config.WhichOneof('value')
    if value_type == 'text_value':
        carrier_config_subelement = ET.SubElement(
            carrier_config_element,
            'string',
        )
        carrier_config_subelement.set('name', config.key)
        carrier_config_subelement.text = getattr(config, value_type)
    elif value_type == 'int_value':
        carrier_config_subelement = ET.SubElement(
            carrier_config_element,
            'int',
        )
        carrier_config_subelement.set('name', config.key)
        carrier_config_subelement.set(
            'value',
            str(getattr(config, value_type)),
        )
    elif value_type == 'long_value':
        carrier_config_subelement = ET.SubElement(
            carrier_config_element,
            'long',
        )
        carrier_config_subelement.set('name', config.key)
        carrier_config_subelement.set(
            'value',
            str(getattr(config, value_type)),
        )
    elif value_type == "bool_value":
        carrier_config_subelement = ET.SubElement(
            carrier_config_element,
            'boolean',
        )
        carrier_config_subelement.set('name', config.key)
        carrier_config_subelement.set(
            'value',
            str(getattr(config, value_type)).lower(),
        )
    elif value_type == 'text_array':
        carrier_config_subelement = ET.SubElement(
            carrier_config_element,
            'string-array',
        )
        carrier_config_subelement.set('name', config.key)
        carrier_config_subelement.set(
            'num',
            str(len(getattr(config, value_type).item)),
        )
        for value in getattr(config, value_type).item:
            carrier_config_item = ET.SubElement(
                carrier_config_subelement,
                'item',
            )
            carrier_config_item.set('value', value)
    elif value_type == 'int_array':
        carrier_config_subelement = ET.SubElement(
            carrier_config_element,
            'int-array',
        )
        carrier_config_subelement.set('name', config.key)
        carrier_config_subelement.set(
            'num',
            str(len(getattr(config, value_type).item)),
        )
        for value in getattr(config, value_type).item:
            carrier_config_item = ET.SubElement(
                carrier_config_subelement,
                'item',
            )
            carrier_config_item.set('value', str(value))
    elif value_type == 'bundle':
        carrier_config_subelement = ET.SubElement(
            carrier_config_element,
            'pbundle_as_map',
        )
        carrier_config_subelement.set('name', config.key)
        for value in getattr(config, value_type).config:
            extract_elements(carrier_config_subelement, value)
    elif value_type == 'double_value':
        carrier_config_subelement = ET.SubElement(
            carrier_config_element,
            'double',
        )
        carrier_config_subelement.set('name', config.key)
        carrier_config_subelement.set(
            'value',
            str(getattr(config, value_type)),
        )
    else:
        raise TypeError("Unknown value type: {}".format(value_type))


def extract_gps_elements(carrier_config_element, config):
    if not config.key.startswith('gps.'):
        return
    extract_elements(carrier_config_element, config)


def main():
    args = parse_args()

    input_folder = args.input
    apns_folder = args.apns
    vendor_folder = args.vendor

    carrier_id_list = CarrierIdList()
    carrier_attribute_map = {}
    with open(os.path.join(os.path.abspath(os.path.dirname(__file__)), 'carrier_list.pb'), 'rb') as pb:
        carrier_id_list.ParseFromString(pb.read())
    for carrier_id_obj in carrier_id_list.carrier_id:
        for carrier_attribute in carrier_id_obj.carrier_attribute:
            for carrier_attributes in product(*(
                    (s.lower() for s in getattr(carrier_attribute, i) or [''])
                    for i in [
                            'mccmnc_tuple', 'imsi_prefix_xpattern', 'spn', 'plmn',
                            'gid1', 'preferred_apn', 'iccid_prefix',
                            'privilege_access_rule',
                    ]
            )):
                carrier_attribute_map[carrier_attributes] = \
                    carrier_id_obj.canonical_id

    carrier_list = CarrierList()
    all_settings = {}

    carrier_list.ParseFromString(open(os.path.join(input_folder, 'carrier_list.pb'), 'rb').read())
    # Load generic settings first
    multi_settings = MultiCarrierSettings()
    multi_settings.ParseFromString(open(os.path.join(input_folder, 'others.pb'), 'rb').read())
    for setting in multi_settings.setting:
        all_settings[setting.canonical_name] = setting
    # Load carrier specific files last, to allow overriding generic settings
    for filename in glob(os.path.join(input_folder, '*.pb')):
        with open(filename, 'rb') as pb:
            if os.path.basename(filename) == 'carrier_list.pb':
                # Handled above already
                continue
            elif os.path.basename(filename) == 'others.pb':
                # Handled above already
                continue
            else:
                setting = CarrierSettings()
                setting.ParseFromString(pb.read())
                if setting.canonical_name in all_settings:
                    print("Overriding generic settings for " + setting.canonical_name, file=sys.stderr)
                all_settings[setting.canonical_name] = setting

    carrier_config_root = ET.Element('carrier_config_list')
    carrier_config_no_sim_root = ET.Element('carrier_config_list')

    # Unfortunately, python processors like xml and lxml, as well as command-line
    # utilities like tidy, do not support the exact style used by AOSP for
    # apns-conf.xml:
    #
    #  * indent: 2 spaces
    #  * attribute indent: 4 spaces
    #  * blank lines between elements
    #  * attributes after first indented on separate lines
    #  * closing tags of multi-line elements on separate, unindented lines
    #
    # Therefore, we build the file without using an XML processor.

    class ApnElement:
        def __init__(self, apn, carrier_id):
            self.apn = apn
            self.carrier_id = carrier_id
            self.attributes = OrderedDict()
            self.add_attributes()

        def add_attribute(self, key, field=None, value=None):
            if value is not None:
                self.attributes[key] = value
            else:
                if field is None:
                    field = key
                if self.apn.HasField(field):
                    enum_type = self.apn.DESCRIPTOR.fields_by_name[field].enum_type
                    value = getattr(self.apn, field)
                    if key == 'skip_464xlat':
                        self.attributes[key] = str(value - 1)
                    elif enum_type is None:
                        if isinstance(value, bool):
                            self.attributes[key] = str(value).lower()
                        else:
                            self.attributes[key] = str(value)
                    else:
                        self.attributes[key] = \
                            enum_type.values_by_number[value].name

        def add_attributes(self):
            try:
                self.add_attribute(
                    'carrier_id',
                    value=str(carrier_attribute_map[(
                        self.carrier_id.mcc_mnc,
                        self.carrier_id.imsi,
                        self.carrier_id.spn.lower(),
                        '',
                        self.carrier_id.gid1.lower(),
                        '',
                        '',
                        '',
                    )])
                )
            except KeyError:
                pass
            self.add_attribute('mcc', value=self.carrier_id.mcc_mnc[:3])
            self.add_attribute('mnc', value=self.carrier_id.mcc_mnc[3:])
            self.add_attribute('apn', 'value')
            self.add_attribute('proxy')
            self.add_attribute('port')
            self.add_attribute('mmsc')
            self.add_attribute('mmsproxy', 'mmsc_proxy')
            self.add_attribute('mmsport', 'mmsc_proxy_port')
            self.add_attribute('user')
            self.add_attribute('password')
            self.add_attribute('server')
            self.add_attribute('authtype')
            self.add_attribute(
                'type',
                value=','.join(
                    apn.DESCRIPTOR.fields_by_name[
                        'type'
                    ].enum_type.values_by_number[i].name
                    for i in self.apn.type
                ).lower(),
            )
            self.add_attribute('protocol')
            self.add_attribute('roaming_protocol')
            self.add_attribute('carrier_enabled')
            self.add_attribute('bearer_bitmask')
            self.add_attribute('profile_id')
            self.add_attribute('modem_cognitive')
            self.add_attribute('max_conns')
            self.add_attribute('wait_time')
            self.add_attribute('max_conns_time')
            self.add_attribute('mtu')
            mvno = self.carrier_id.WhichOneof('mvno_data')
            if mvno:
                self.add_attribute(
                    'mvno_type',
                    value='gid' if mvno.startswith('gid') else mvno,
                )
                self.add_attribute(
                    'mvno_match_data',
                    value=getattr(self.carrier_id, mvno),
                )
            self.add_attribute('apn_set_id')
            # No source for integer carrier_id?
            self.add_attribute('skip_464xlat')
            self.add_attribute('user_visible')
            self.add_attribute('user_editable')

    if apns_folder is not None:
        with open(os.path.join(apns_folder, 'apns-conf.xml'), 'w', encoding='utf-8') as f:
            f.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n\n')
            f.write('<apns version="8">\n\n')

            for entry in carrier_list.entry:
                try:
                    setting = all_settings[entry.canonical_name]
                except KeyError:
                    print("Skipping " + entry.canonical_name, file=sys.stderr)
                    continue
                for apn in setting.apns.apn:
                    f.write('  <apn carrier={}\n'.format(quoteattr(apn.name)))
                    apn_element = ApnElement(apn, entry.carrier_id[0])
                    for (key, value) in apn_element.attributes.items():
                        f.write('      {}={}\n'.format(escape(key), quoteattr(value)))
                    f.write('  />\n\n')

            f.write('</apns>\n')

        # Test XML parsing.
        ET.parse(os.path.join(apns_folder, 'apns-conf.xml'))

    for entry in carrier_list.entry:
        try:
            setting = all_settings[entry.canonical_name]
        except KeyError:
            print("Skipping " + entry.canonical_name, file=sys.stderr)
            continue

        carrier_config_element = ET.SubElement(
            carrier_config_root,
            'carrier_config',
        )
        mcc = entry.carrier_id[0].mcc_mnc[:3]
        mnc = entry.carrier_id[0].mcc_mnc[3:]
        if (mcc == '000' and mnc == '000'):
            carrier_config_no_sim_element = ET.SubElement(
                carrier_config_no_sim_root,
                'carrier_config',
            )
            for config in setting.configs.config:
                extract_gps_elements(carrier_config_no_sim_element, config)
        else:
            carrier_config_element.set('mcc', mcc)
            carrier_config_element.set('mnc', mnc)
        for field in ['spn', 'imsi', 'gid1']:
            if entry.carrier_id[0].HasField(field):
                carrier_config_element.set(
                    field,
                    getattr(entry.carrier_id[0], field),
                )
        for config in setting.configs.config:
            extract_elements(carrier_config_element, config)

    indent(carrier_config_root)
    carrier_config_tree = ET.ElementTree(carrier_config_root)
    carrier_config_tree.write(os.path.join(vendor_folder, 'vendor.xml'),
                              encoding='utf-8', xml_declaration=True)
    indent(carrier_config_no_sim_root)
    carrier_config_no_sim_tree = ET.ElementTree(carrier_config_no_sim_root)
    carrier_config_no_sim_tree.write(os.path.join(vendor_folder, 'vendor_no_sim.xml'),
                              encoding='utf-8', xml_declaration=True)

    # Test XML parsing.
    ET.parse(os.path.join(vendor_folder, 'vendor.xml'))
    ET.parse(os.path.join(vendor_folder, 'vendor_no_sim.xml'))

if __name__ == '__main__':
    main()
