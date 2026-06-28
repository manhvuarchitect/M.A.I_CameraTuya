package tuya

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
	"tuya-ipc-terminal/pkg/core"
	"tuya-ipc-terminal/pkg/utils"
)

type MQTTCameraClient struct {
	mqttClient   *MQTTClient
	webrtcConfig *WebRTCConfig

	auth         string
	motoId       string
	deviceId     string
	SessionId    string
	publishTopic string

	HandleAnswer     func(answer AnswerFrame)
	HandleCandidate  func(candidate CandidateFrame)
	HandleDisconnect func()
	HandleError      func(err error)
}

type Replay struct {
	IsReplay int `json:"is_replay"`
}

type OfferFrame struct {
	Mode              string      `json:"mode"`
	Sdp               string      `json:"sdp"`
	StreamType        int         `json:"stream_type"`
	Auth              string      `json:"auth"`
	DatachannelEnable bool        `json:"datachannel_enable"`
	Token             []ICEServer `json:"token"`
}

type AnswerFrame struct {
	Mode string `json:"mode"`
	Sdp  string `json:"sdp"`
}

type CandidateFrame struct {
	Mode      string `json:"mode"`
	Candidate string `json:"candidate"`
}

type ResolutionFrame struct {
	Mode  string `json:"mode"`
	Value int    `json:"cmdValue"` // 0: HD, 1: SD
}

type SpeakerFrame struct {
	Mode  string `json:"mode"`
	Value int    `json:"cmdValue"` // 0: off, 1: on
}

type DisconnectFrame struct {
	Mode string `json:"mode"`
}

func NewMqttCameraClient(mqttClient *MQTTClient, device *Device, webrtcConfig *WebRTCConfig) *MQTTCameraClient {
	topic := mqttClient.publishTopicBase
	topic = strings.Replace(topic, "moto_id", webrtcConfig.MotoId, 1)
	topic = strings.Replace(topic, "{device_id}", device.DeviceId, 1)

	return &MQTTCameraClient{
		mqttClient:   mqttClient,
		webrtcConfig: webrtcConfig,
		auth:         webrtcConfig.Auth,
		motoId:       webrtcConfig.MotoId,
		deviceId:     device.DeviceId,
		SessionId:    utils.RandString(6, 62),
		publishTopic: topic,
	}
}

func (c *MQTTCameraClient) SendOffer(sdp string, streamResolution string, streamType int, isHEVC bool) error {
	if streamResolution == "hd" {
		streamType = 0
	} else {
		streamType = 1
	}

	return c.sendMqttMessage("offer", 302, "", OfferFrame{
		Mode:              "webrtc",
		Sdp:               sdp,
		StreamType:        streamType,
		Auth:              c.auth,
		DatachannelEnable: isHEVC,
		Token:             c.webrtcConfig.P2PConfig.Ices,
	})
}

func (c *MQTTCameraClient) SendCandidate(candidate string) error {
	return c.sendMqttMessage("candidate", 302, "", CandidateFrame{
		Mode:      "webrtc",
		Candidate: candidate,
	})
}

func (c *MQTTCameraClient) SendResolution(resolution int) error {
	// isClaritySupperted := (c.webrtcVersion & (1 << 5)) != 0
	// if !isClaritySupperted {
	// 	return nil
	// }

	// Protocol 312 is used for clarity
	return c.sendMqttMessage("resolution", 312, "", ResolutionFrame{
		Mode:  "webrtc",
		Value: resolution,
	})
}

func (c *MQTTCameraClient) SendSpeaker(speaker int) error {
	// Protocol 312 is used for speaker
	return c.sendMqttMessage("speaker", 312, "", SpeakerFrame{
		Mode:  "webrtc",
		Value: speaker,
	})
}

func (c *MQTTCameraClient) SendDisconnect() error {
	return c.sendMqttMessage("disconnect", 302, "", DisconnectFrame{
		Mode: "webrtc",
	})
}

func (c *MQTTCameraClient) onMqttAnswer(msg *MqttMessage) {
	var answerFrame AnswerFrame
	if err := json.Unmarshal(msg.Data.Message, &answerFrame); err != nil {
		c.onError(err)
		return
	}

	c.onAnswer(answerFrame)
}

func (c *MQTTCameraClient) onMqttCandidate(msg *MqttMessage) {
	var candidateFrame CandidateFrame
	if err := json.Unmarshal(msg.Data.Message, &candidateFrame); err != nil {
		c.onError(err)
		return
	}

	// candidate from device start with "a=", end with "\r", which are not needed by Chrome webRTC
	candidateFrame.Candidate = strings.TrimPrefix(candidateFrame.Candidate, "a=")
	candidateFrame.Candidate = strings.TrimSuffix(candidateFrame.Candidate, "\r")

	c.onCandidate(candidateFrame)
}

func (c *MQTTCameraClient) onMqttDisconnect() {
	c.onDisconnect()
}

func (c *MQTTCameraClient) onAnswer(answer AnswerFrame) {
	if c.HandleAnswer != nil {
		c.HandleAnswer(answer)
	}
}

func (c *MQTTCameraClient) onCandidate(candidate CandidateFrame) {
	if c.HandleCandidate != nil {
		c.HandleCandidate(candidate)
	}
}

func (c *MQTTCameraClient) onDisconnect() {
	if c.HandleDisconnect != nil {
		c.HandleDisconnect()
	}
}

func (c *MQTTCameraClient) onError(err error) {
	if c.HandleError != nil {
		c.HandleError(err)
	}
}

func (c *MQTTCameraClient) sendMqttMessage(messageType string, protocol int, transactionID string, data interface{}) error {
	if c.mqttClient.closed {
		return errors.New("mqtt client is closed, send mqtt message fail")
	}

	jsonMessage, err := json.Marshal(data)
	if err != nil {
		return err
	}

	msg := &MqttMessage{
		Protocol: protocol,
		Pv:       "2.2",
		T:        time.Now().Unix(),
		Data: MqttFrame{
			Header: MqttFrameHeader{
				Type:          messageType,
				From:          c.mqttClient.uid,
				To:            c.deviceId,
				SessionID:     c.SessionId,
				MotoID:        c.motoId,
				TransactionID: transactionID,
			},
			Message: jsonMessage,
		},
	}

	payload, err := json.Marshal(msg)
	if err != nil {
		return err
	}

	core.Logger.Trace().Msgf("Sending MQTT payload to %s: %s", c.publishTopic, string(payload))

	token := c.mqttClient.mqtt.Publish(c.publishTopic, 1, false, payload)
	if token.Wait() && token.Error() != nil {
		core.Logger.Error().Err(token.Error()).Msgf("Send mqtt message error")
		return token.Error()
	}

	return nil
}
